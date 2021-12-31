# frozen_string_literal: true

module Haml::Util
  def self.unescape_interpolation_to_original_cache
    Thread.current[:haml_lint_unescape_interpolation_to_original_cache] ||= {}
  end

  def self.unescape_interpolation_to_original_cache_take_and_wipe
    value = unescape_interpolation_to_original_cache.dup
    unescape_interpolation_to_original_cache.clear
    value
  end

  # Haml does heavy transformations to strings that contain interpolation
  # We use this monkey patch to have a way of recovering the original strings
  # as they are in the haml files.
  def unescape_interpolation_with_original_tracking(str, escape_html = nil)
    value = unescape_interpolation_without_original_tracking(str, escape_html)
    Haml::Util.unescape_interpolation_to_original_cache[value] = str
    value
  end

  alias_method :unescape_interpolation_without_original_tracking, :unescape_interpolation
  alias_method :unescape_interpolation, :unescape_interpolation_with_original_tracking
end

module HamlLint::RubyExtraction
  class ChunkExtractor
    include HamlLint::HamlVisitor

    def initialize(document)
      @document = document
      @indent_level = 0
    end

    def assembler
      ruby_chunks = extract
      HamlLint::RubyExtraction::ChunkAssembler.new(
          @document,
          ruby_chunks,
          script_output_prefix: script_output_prefix
      )
    end

    def extract
      return @ruby_chunks if @ruby_chunks
      @ruby_chunks = []
      @original_haml_lines = @document.source_lines

      visit(@document.tree)
      @ruby_chunks
    end

    def visit_root(node)
      yield # Collect lines of code from children
    end

    def visit_plain(node)
      @ruby_chunks << PlaceholderChunk.new(node, ["#{'  ' * @indent_level}haml_lint_plain_placeholder"],
                                           end_marker_indent_level: nil)
    end

    def visit_script(node) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      lines = raw_lines_of_interest(node.line)

      if lines.first !~ /\A\s*[-=]/
        # The line doesn't start with a - or a =, this is actually a "plain"
        # that contains interpolation.

        if node.text.lines.size > 1
          #Can that happen?
          binding.pry
        end

        add_interpolation_chunks(node, lines.first, node.line)
        return
      end

      lines[0] = lines[0].sub(/(=[ \t]*)/, '')
      line_indentation = $1.size

      raw_code = lines.join("\n")
      start_block = self.class.anonymous_block?(raw_code) || self.class.start_block_keyword?(raw_code)
      case_block = self.class.block_keyword(raw_code) == 'case'

      lines[0] = HamlLint::Utils.insert_after_indentation(lines[0], script_output_prefix)

      indent_delta = script_output_prefix.size - line_indentation
      (1...lines.size).each do |i|
        lines[i] = HamlLint::Utils.indent(lines[i], indent_delta)
      end

      prev_chunk = @ruby_chunks.last
      if prev_chunk.is_a?(ScriptChunk) && prev_chunk.node.type == :script && prev_chunk.node == node.parent
        # When an outputting script is nested under another outputting script,
        # we want to block them from being merged together by rubocop, because
        # this doesn't make sense in HAML.
        # Example:
        #   = if this_is_short
        #     = this_is_short_too
        # Could become (after RuboCop):
        #   HL.out = (HL.out = this_is_short_too if this_is_short)
        # Or in (broken) HAML style:
        #   = this_is_short_too = if this_is_short
        # By forcing this to start a chunk, there will be extra placeholders
        must_start_chunk = true
      end

      increment_indent if start_block
      increment_indent if case_block

      @ruby_chunks << ScriptChunk.new(node, lines, end_marker_indent_level: @indent_level,
                                      must_start_chunk: must_start_chunk)

      yield

      decrement_indent if case_block
      if start_block
        decrement_indent
        @ruby_chunks << ImplicitEndChunk.new(node, ["#{'  ' * @indent_level}end"],
                                             haml_start_line: @ruby_chunks.last.haml_end_line,
                                             end_marker_indent_level: @indent_level)
      end
    end

    def visit_silent_script(node, &block)
      lines = raw_lines_of_interest(node.line)
      lines[0] = lines[0].sub(/(-[ \t]*)/, '')
      nb_to_deindent = $1.size

      (1...lines.size).each do |i|
        lines[i] = lines[i].sub(/^ {1,#{nb_to_deindent}}/, '')
      end

      code = lines.join("\n")
      start_block = self.class.anonymous_block?(code) || self.class.start_block_keyword?(code)
      case_block = self.class.block_keyword(code) == 'case'

      increment_indent if start_block
      increment_indent if case_block # Cases are actually double nested

      @ruby_chunks << ScriptChunk.new(node, lines, end_marker_indent_level: @indent_level)

      yield

      decrement_indent if case_block
      if start_block
        decrement_indent
        @ruby_chunks << ImplicitEndChunk.new(node, ["#{'  ' * @indent_level}end"],
                                             haml_start_line: @ruby_chunks.last.haml_end_line,
                                             end_marker_indent_level: @indent_level)
      end
    end

    def visit_tag(node)
      has_children = !node.children.empty?
      if has_children
        @ruby_chunks << PlaceholderChunk.new(node, ["#{'  ' * @indent_level}if haml_lint_tag_indent"],
                                             end_marker_indent_level: nil)

        increment_indent
      end

      # Always placing this placeholder so that if there can't be only one thing
      # inside of the `if haml_lint_tag_indent`. This avoids the risk of RuboCop
      # deciding that the `if` should be a modifier.
      @ruby_chunks << PlaceholderChunk.new(node, ["#{'  ' * @indent_level}haml_lint_tag_placeholder"],
                                           end_marker_indent_level: nil)
      additional_attributes = node.dynamic_attributes_sources
      if additional_attributes.size > 1
        binding.pry
      end

      attributes_code = additional_attributes.first
      if !attributes_code && node.hash_attributes? && node.dynamic_attributes_sources.empty?
        # No idea why .foo{:bar => 123} doesn't get here, but .foo{:bar => '123'} does...
        # The code we get for the later is {:bar => '123'}.
        # We normalize it by removing the { } so that it matches wha we normally get
        attributes_code = node.dynamic_attributes_source[:hash][1...-1]
      end

      if attributes_code
        # Attributes have different ways to be given to us:
        #   .foo{bar: 123} => "bar: 123"
        #   .foo{:bar => 123} => ":bar => 123"
        #   .foo{:bar => '123'} => "{:bar => '123'}" # No idea why this is different
        #   .foo(bar = 123) => '{"bar" => 123,}'
        #   .foo{html_attrs('fr-fr')} => html_attrs('fr-fr')
        # The (bar = 123) case is extra painful to autocorrect unless we allow
        # transforming it into hash style, for now we don't. #raw_ruby_from_haml
        # will detect this case by not finding the code.
        # We wrap the result in a method to have a valid syntax for all 3 ways
        # without having to differentiate them.
        first_line_offset, raw_attributes_lines = raw_ruby_lines_from_haml(attributes_code, node.line)

        # Since .foo{bar: 123} => "bar: 123" needs wrapping (Or it would be a syntax error) and
        # .foo{html_attrs('fr-fr')} => html_attrs('fr-fr') doesn't care about being
        # wrapped, we always wrap to place them similar to how they are in the code.

        if raw_attributes_lines
          wrap_by = first_line_offset - @indent_level * 2
          if wrap_by < 2
            # Need 2 minimum, for "W("
            extra_indent = 2 - wrap_by
            raw_attributes_lines[1..-1] = raw_attributes_lines[1..-1].map do |line|
              ' ' * extra_indent + line
            end
            wrap_by = 2
          end
          raw_attributes_lines = wrap_lines(raw_attributes_lines, wrap_by)
          raw_attributes_lines[0] = '  ' * @indent_level + raw_attributes_lines[0]

          @ruby_chunks << TagAttributesChunk.new(node, raw_attributes_lines,
                                                 end_marker_indent_level: @indent_level,
                                                 indent_to_remove: extra_indent)
        end
      end

      if node.script && !node.script.empty?
        line_number = node.line
        line_number += raw_attributes_lines.size - 1 if raw_attributes_lines

        first_line_offset, script_lines = raw_ruby_lines_from_haml(node.script, line_number)

        if script_lines.nil?
          interpolation_original = @document.unescape_interpolation_to_original_cache[node.script]
          if interpolation_original
            # This is a string with interpolation after a tag
            # ex: %tag hello #{world}
            line_start_index = @original_haml_lines[node.line - 1].rindex(interpolation_original)
            add_interpolation_chunks(node, interpolation_original, node.line, line_start_index: line_start_index)
          else
            binding.pry
          end
        else
          script_lines[0] = "#{'  ' * @indent_level}#{script_output_prefix}#{script_lines[0]}"
          indent_delta = script_output_prefix.size - first_line_offset + @indent_level * 2
          (1...script_lines.size).each do |i|
            script_lines[i] = HamlLint::Utils.indent(script_lines[i], indent_delta)
          end

          @ruby_chunks << TagScriptChunk.new(node, script_lines,
                                             haml_start_line: line_number,
                                             end_marker_indent_level: @indent_level)
        end
      end

      if has_children
        yield
        decrement_indent
        @ruby_chunks << ImplicitEndChunk.new(node, ["#{'  ' * @indent_level}end"],
                                             haml_start_line: @ruby_chunks.last.haml_end_line,
                                             end_marker_indent_level: nil)
      end
    end

    def visit_filter(node)
      if node.filter_type == 'ruby'
        # The indentation in node.text is normalized, so that at least one line
        # is not indented.
        lines = node.text.split("\n")
        indent = '  ' * @indent_level
        lines.map! do |line|
          if line !~ /\S/
            # whitespace or empty
            ''
          else
            indent + line
          end
        end

        @ruby_chunks << RubyFilterChunk.new(node, lines,
                                            haml_start_line: node.line + 1,
                                            end_marker_indent_level: @indent_level)
      else
        nb_chunks_before = @ruby_chunks.size
        # For unknown reasons, haml doesn't escape interpolations in filters.
        # This makes them easier to handle than plain (script) which have interpolation.
        node.text.split("\n").each.with_index do |line, i|
          add_interpolation_chunks(node, @original_haml_lines[node.line + i], node.line + i + 1)
        end

        if nb_chunks_before == @ruby_chunks.size
          # Since there was no interpolation, add a placeholder
          @ruby_chunks << PlaceholderChunk.new(node, ["#{'  ' * @indent_level}haml_lint_filter_placeholder"],
                                               end_marker_indent_level: nil)
        end
      end
    end

    def add_interpolation_chunks(node, line, haml_line_number, line_start_index: 0)
      Haml::Util.handle_interpolation(line) do |scanner|
        escapes = scanner[2].size
        next if escapes % 2 == 1
        char = scanner[3] # '{', '@' or '$'
        if Gem::Version.new(Haml::VERSION) >= Gem::Version.new('5')
          # Before Haml 5, scanner didn't have a 3rd group, it only handled `#{}`
          next if char != '{'
        end

        start_char_index = line_start_index + scanner.pos
        interpolated_code = Haml::Util.balance(scanner, ?{, ?}, 1)[0][0...-1]
        interpolated_code = '  ' * @indent_level + script_output_prefix + interpolated_code
        @ruby_chunks << InterpolationChunk.new(node, [interpolated_code],
                                               haml_start_line: haml_line_number,
                                               start_char_index: start_char_index,
                                               end_marker_indent_level: @indent_level)
      end
    end

    def raw_lines_of_interest(first_line_number)
      line_index = first_line_number - 1
      lines_of_interest = [@original_haml_lines[line_index]]

      while @original_haml_lines[line_index].rstrip.end_with?(',')
        line_index += 1
        lines_of_interest << @original_haml_lines[line_index]
      end

      lines_of_interest
    end

    # Haml's line-splitting rules (allowed after comma in scripts and attributes) are handled
    # at the parser level, so Haml doesn't provide the code as it is actually formatted in the Haml
    # file. #raw_ruby_from_haml extracts the ruby code as it is exactly in the file.
    def raw_ruby_lines_from_haml(code, first_line_number)
      stripped_code = code.strip
      return if stripped_code.empty?

      lines_of_interest = raw_lines_of_interest(first_line_number)

      if lines_of_interest.size == 1
        index = lines_of_interest.first.index(stripped_code)
        if lines_of_interest.first.include?(stripped_code)
          return [index, [stripped_code]]
        else
          return
        end
      end

      raw_haml = lines_of_interest.join("\n")

      # Need the gsub because while multiline scripts are turned into a single line,
      # by haml, multiline tag attributes are not.
      code_parts = stripped_code.gsub("\n", ' ').split(/,\s*/)

      regexp_code = code_parts.map { |c| Regexp.quote(c) }.join(',\\s*')
      regexp = Regexp.new(regexp_code)

      match = raw_haml.match(regexp)

      raw_ruby = match[0]
      ruby_lines = raw_ruby.split("\n")
      first_line_offset = match.begin(0)

      [first_line_offset, ruby_lines]
    end

    def wrap_lines(lines, wrap_depth)
      lines = lines.dup
      wrapping_prefix = "W" * (wrap_depth - 1) + "("
      lines[0] = wrapping_prefix + lines[0]
      lines[-1] = lines[-1] + ")"
      lines
    end

    def increment_indent
      @indent_level += 1
    end

    def decrement_indent
      @indent_level -= 1
    end

    def script_output_prefix
      return @script_output_prefix if @script_output_prefix
      # TODO, check if the file contains this, and change to something else if it does
      @script_output_prefix = 'HL.out = '
    end

    def self.anonymous_block?(text)
      text =~ /\bdo\s*(\|\s*[^\|]*\s*\|)?(\s*#.*)?\z/
    end

    START_BLOCK_KEYWORDS = %w[if unless case begin for until while].freeze
    def self.start_block_keyword?(text)
      START_BLOCK_KEYWORDS.include?(block_keyword(text))
    end

    MID_BLOCK_KEYWORDS = %w[else elsif when rescue ensure].freeze
    def self.mid_block_keyword?(text)
      MID_BLOCK_KEYWORDS.include?(block_keyword(text))
    end

    LOOP_KEYWORDS = %w[for until while].freeze
    def self.block_keyword(text)
      # Need to handle 'for'/'while' since regex stolen from HAML parser doesn't
      if keyword = text[/\A\s*([^\s]+)\s+/, 1]
        return keyword if LOOP_KEYWORDS.include?(keyword)
      end

      return unless keyword = text.scan(Haml::Parser::BLOCK_KEYWORD_REGEX)[0]
      keyword[0] || keyword[1]
    end
  end
end
