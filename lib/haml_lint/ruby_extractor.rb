# frozen_string_literal: true

require 'pry'
# rubocop:disable Metrics/AbcSize, Metrics/MethodLength
module HamlLint
  # Utility class for extracting Ruby script from a HAML file that can then be
  # linted with a Ruby linter (i.e. is "legal" Ruby). The goal is to turn this:
  #
  #     - if signed_in?(viewer)
  #       %span Stuff
  #       = link_to 'Sign Out', sign_out_path
  #     - else
  #       .some-class{ class: my_method }= my_method
  #       = link_to 'Sign In', sign_in_path
  #
  # into this:
  #
  #     if signed_in?(viewer)
  #       link_to 'Sign Out', sign_out_path
  #     else
  #       { class: my_method }
  #       my_method
  #       link_to 'Sign In', sign_in_path
  #     end
  #
  # The translation won't be perfect, and won't make any real sense, but the
  # relationship between variable declarations/uses and the flow control graph
  # will remain intact.
  class RubyExtractor # rubocop:disable Metrics/ClassLength
    include HamlVisitor

    # Stores the extracted source and a map of lines of generated source to the
    # original source that created them.
    #
    # @attr_reader source [String] generated source code
    # @attr_reader source_map [Hash] map of line numbers from generated source
    #   to original source line number
    # TODO @attr_reader autocorrectable_chunks
    RubySource = Struct.new(:source, :source_map, :autocorrectable_chunks)

    # Internal class to track info on an individual autocorrectable chunk of code
    class AutocorrectableChunk
      # @return [HamlLint::Tree::Node] Haml node that this comes from
      attr_reader :node

      # @return [Integer] First line number of the autocorrectable code in the Haml source
      attr_reader :haml_start_line

      # @return [Integer] Line number of the line marker in the ruby source placed before
      #                   this autocorrectable code
      attr_reader :start_marker_line

      # @return [Integer] Line number of the line marker in the ruby source placed after
      #                   this autocorrectable code
      attr_reader :end_marker_line

      # @return [Integer] The indent_level that was applied to this code
      attr_reader :indent_level

      # @return [Integer] If not nil, then the code was wrapped with W*(...) (variable number of W)
      #   Wrapping is needed to handle tag attributes and multiline code that
      #   has a line less indented than the first.
      #   Higher number than 0 means that some of that offset is needed for correct
      #   alignment in case of multi-line code with less indentation.
      attr_reader :wrap_offset_to_keep

      # TODO
      attr_reader :haml_indentation

      # @return [Boolean] If true, every line except the last needs to end with a comma
      #   This is the basic line splitting rule of haml

      def initialize(node, haml_start_line, start_marker_line, end_marker_line, # rubocop:disable Metrics/ParameterLists
                     indent_level, wrap_offset_to_keep, comma_changes_line,
                     haml_indentation)
        @node = node
        @haml_start_line = haml_start_line
        @start_marker_line = start_marker_line
        @end_marker_line = end_marker_line
        @indent_level = indent_level
        @wrap_offset_to_keep = wrap_offset_to_keep
        @comma_changes_line = comma_changes_line
        @haml_indentation = haml_indentation
      end

      def extract_from(source_lines)
        cur_start_marker_index = self.class.find_marker_index(source_lines, @start_marker_line)
        return if cur_start_marker_index.nil?

        cur_end_marker_index = self.class.find_marker_index(source_lines, @end_marker_line)
        return if cur_end_marker_index.nil?

        lines = source_lines[(cur_start_marker_index + 1)..(cur_end_marker_index - 1)]
        if @wrap_offset_to_keep
          lines = lines.map(&:dup)
          nb_to_deindent = lines[0][/W+\(/].size - @wrap_offset_to_keep
          lines[0].sub!(/W+\(/, '')

          lines[1..-1].each { |l| l.sub!(/^ {1,#{nb_to_deindent}}/, '') }
          lines[-1].sub!(/\)\s*\Z/, '')
        end

        lines
      end

      # Finds the line marker in the given source_lines
      def self.find_marker_index(source_lines, line)
        marker = "#{AUTOCORRECT_MARKER_PREFIX}#{line}"

        # In the best cases, the line didn't move
        # Using end_with? because indentation may have been added
        return line - 1 if source_lines[line - 1]&.end_with?(marker)

        source_lines.index { |l| l.end_with?(marker) }
      end

      def transfer_correction(initial_ruby_lines, corrected_ruby_lines, haml_lines)
        from_ruby_lines = extract_from(initial_ruby_lines)
        to_ruby_lines = extract_from(corrected_ruby_lines)

        if @comma_changes_line
          # Rubocop can sometimes move code around which is not directly comparible with haml's
          # rule for splitting lines. Skip those corrections.
          return if to_ruby_lines[0...-1].any? { |l| l !~ /,[ \t]*\n?\Z/ }
          return if to_ruby_lines[-1] =~ /,[ \t]*\n?\Z/
        end

        haml_start_line_index = @haml_start_line - 1
        nb_lines = [from_ruby_lines.size, to_ruby_lines.size].max
        char_index = nil
        first_missing_line_index = nil

        nb_lines.times do |i|
          from_ruby_line = from_ruby_lines[i]
          to_ruby_line = to_ruby_lines[i]

          if from_ruby_line.nil?
            haml_lines.insert(haml_start_line_index + i, ' ' * char_index + to_ruby_line)
            # Need to test without the rstrip!
            haml_lines[haml_start_line_index + i].rstrip!
          elsif to_ruby_line.nil?
            first_missing_line_index ||= haml_start_line_index + i
            haml_lines.delete_at(first_missing_line_index)
          else
            haml_line = haml_lines[haml_start_line_index + i].dup
            haml_lines[haml_start_line_index + i] = haml_line

            from_ruby_line = HamlLint::Utils.indent(from_ruby_line, -@indent_level * 2)
            to_ruby_line = HamlLint::Utils.indent(to_ruby_line, -@indent_level * 2)

            if @haml_indentation
              char_index = @haml_indentation
              if haml_line.size < char_index
                haml_line << ' ' * (char_index - haml_line.size)
              end
            else
              char_index = haml_line.index(from_ruby_line)
            end

            haml_line[char_index...(char_index + from_ruby_line.size)] = to_ruby_line
            haml_line.rstrip!
          end
        end
      end
    end

    #AUTOCORRECT_MARKER_PREFIX = '# Haml-lint-autocorrectable-'
    AUTOCORRECT_MARKER_PREFIX = 'haml_lint_autocorrectable_'

    # Extracts Ruby code from Sexp representing a Slim document.
    #
    # @param document [HamlLint::Document]
    # @return [HamlLint::RubyExtractor::RubySource]
    def extract(document, autocorrect: nil)
      @original_haml_lines = document.source_lines
      @autocorrect = autocorrect
      visit(document.tree)

      ruby_source = RubySource.new(@source_lines.join("\n"), @source_map, @autocorrectable_chunks)
      # Clear this to avoid risk of mistakes from reusing
      @autocorrectable_chunks = nil
      ruby_source
    end

    # Returns a new haml source which had the compatible fixes from corrected_source
    def haml_lines_with_corrections(haml_lines, extracted_source, corrected_ruby_source)
      corrected_ruby_lines = corrected_ruby_source.split("\n")
      haml_lines = haml_lines.dup

      # Going in reverse order, so that if we change the number of lines then the
      # rest of the file will not be offset, which would make things harder
      extracted_source.autocorrectable_chunks.reverse_each do |ac_chunk|
        ac_chunk.transfer_correction(@source_lines, corrected_ruby_lines, haml_lines)
      end
      haml_lines
    end

    def visit_root(_node)
      @source_lines = []
      @source_map = {}
      @line_count = 0
      @indent_level = 0
      @output_count = 0
      @autocorrectable_chunks = []

      yield # Collect lines of code from children
    end

    def visit_plain(node)
      # Don't output the text, as we don't want to have to deal with any RuboCop
      # cops regarding StringQuotes or AsciiComments, and it's not important to
      # overall document anyway.
      add_dummy_puts(node)
    end

    def visit_tag(node)
      additional_attributes = node.dynamic_attributes_sources

      # Include dummy references to code executed in attributes list
      # (this forces a "use" of a variable to prevent "assigned but unused
      # variable" lints)
      additional_attributes.each do |attributes_code|
        # Attributes have different ways to be given to us:
        #   .foo{bar: 123} => "bar: 123"
        #   .foo(bar = 123) => '{"bar" => 123,}'
        #   .foo{html_attrs('fr-fr')} => html_attrs('fr-fr')
        # We wrap the result in a method to have a valid syntax for all 3 ways
        # without having to differentiate them.
        # The (bar = 123) case is extra painful to autocorrect, so we don't. We detect that
        # by searching for the attributes code in the line

        required_first_offset, raw_attributes_code = extract_raw_script(attributes_code, node.line)
        # We must always wrap attributes, otherwise .foo{bar: 123} will be a syntax error
        required_first_offset ||= 0

        if raw_attributes_code
          add_autocorrectable_line(raw_attributes_code,
                                   node,
                                   wrap_offset_to_keep: required_first_offset)
        else
          # Normalize by removing excess whitespace to avoid format lints
          attributes_code = attributes_code.gsub(/\s*\n\s*/, ' ').strip
          add_line("W(#{attributes_code.strip})", node)
        end
      end

      check_tag_static_hash_source(node)

      # We add a dummy puts statement to represent the tag name being output.
      # This prevents some erroneous RuboCop warnings.
      add_dummy_puts(node, node.tag_name)
      required_first_offset, code = extract_raw_script(node.script, node.line)
      if code && !code.empty?
        add_autocorrectable_line(code,
                                 node,
                                 wrap_offset_to_keep: required_first_offset&.nonzero?)
      end
    end

    def after_visit_tag(node)
      # We add a dummy puts statement for closing tag.
      add_dummy_puts(node, "#{node.tag_name}/")
    end

    def visit_script(node) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      required_first_offset, code = extract_raw_script(node.text, node.line)

      if code
        start_block = anonymous_block?(code) || start_block_keyword?(code)
        add_autocorrectable_line(code,
                                 node,
                                 wrap_offset_to_keep: required_first_offset&.nonzero?,
                                 adds_indent_level: start_block)
      else
        # A line without - or =, but that contains interpollation, ex:
        # Hello #{name}, good day!
        # The interpolation don't seem to allow line splitting on comma
        code = node.text
        start_block = false
        if code.start_with?('"') && code.end_with?('"')
          HamlLint::Utils.extract_interpolated_values(node.text) do |interpolated_code, line|
            add_autocorrectable_line(interpolated_code, node, node.line + line - 1)
          end
        else
          add_line(code, node)
        end
      end

      if start_block
        @indent_level += 1
      end

      yield # Continue extracting code from children

      if start_block
        @indent_level -= 1
        add_line('end', node)
      end
    end

    def visit_haml_comment(node)
      # We want to preseve leading whitespace if it exists, but include leading
      # whitespace if it doesn't exist so that RuboCop's LeadingCommentSpace
      # doesn't complain
      comment = node.text
                    .gsub(/\n(\S)/, "\n# \\1")
                    .gsub(/\n(\s)/, "\n#\\1")
      add_line("##{comment}", node)
    end

    def visit_silent_script(node, &block)
      visit_script(node, &block)
    end

    def visit_filter(node)
      if node.filter_type == 'ruby'
        if @autocorrect
          haml_indentation = @original_haml_lines[node.line - 1].index(/:/) + 2
          add_autocorrectable_line(node.text.rstrip, node, node.line + 1,
                                   comma_changes_line: false, haml_indentation: haml_indentation)
        else
          node.text.split("\n").each_with_index do |line, index|
            add_line(line, node, node.line + index + 1, discard_blanks: false)
          end
        end
      else
        add_dummy_puts(node, ":#{node.filter_type}")
        HamlLint::Utils.extract_interpolated_values(node.text) do |interpolated_code, line|
          add_autocorrectable_line(interpolated_code, node, node.line + line)
        end
      end
    end

    private

    def check_tag_static_hash_source(node)
      # Haml::Parser converts hashrocket-style hash attributes of strings and symbols
      # to static attributes, and excludes them from the dynamic attribute sources:
      # https://github.com/haml/haml/blob/08f97ec4dc8f59fe3d7f6ab8f8807f86f2a15b68/lib/haml/parser.rb#L400-L404
      # https://github.com/haml/haml/blob/08f97ec4dc8f59fe3d7f6ab8f8807f86f2a15b68/lib/haml/parser.rb#L540-L554
      # Here, we add the hash source back in so it can be inspected by rubocop.
      if node.hash_attributes? && node.dynamic_attributes_sources.empty?
        normalized_attr_source = node.dynamic_attributes_source[:hash].gsub(/\s*\n\s*/, ' ')

        add_line(normalized_attr_source, node)
      end
    end

    # Adds a dummy method call with a unique name so we don't get
    # Style/IdenticalConditionalBranches RuboCop warnings
    def add_dummy_puts(node, annotation = nil)
      annotation = " # #{annotation}" if annotation
      add_line("_haml_lint_puts_#{@output_count}#{annotation}", node)
      @output_count += 1
    end

    def add_autocorrectable_line(code, node, haml_line = node.line, wrap_offset_to_keep: false,
                                 comma_changes_line: true, haml_indentation: nil,
                                 adds_indent_level: false)
      if wrap_offset_to_keep
        offsetting_call = if wrap_offset_to_keep > 0
                            'W' * wrap_offset_to_keep
                          else
                            'W'
                          end
        extra_indent = offsetting_call.size + 1 - wrap_offset_to_keep
        code = HamlLint::Utils.indent_lines_after_first(code, extra_indent)
        code = "#{offsetting_call}(#{code})"
      end

      unless @autocorrect
        add_line(code, node, haml_line, discard_blanks: false)
        return
      end
      add_line("#{AUTOCORRECT_MARKER_PREFIX}#{@line_count + 1}", node)
      start_marker_line_number = @line_count
      chunk_indent_level = @indent_level
      code.split("\n").each do |line|
        add_line(line, node, node.line, discard_blanks: false)
      end

      if adds_indent_level
        indent_for_marker = '  '
      end

      add_line("#{indent_for_marker}#{AUTOCORRECT_MARKER_PREFIX}#{@line_count + 1}", node)

      @autocorrectable_chunks << AutocorrectableChunk.new(node,
                                                          haml_line,
                                                          start_marker_line_number,
                                                          @line_count,
                                                          chunk_indent_level,
                                                          wrap_offset_to_keep,
                                                          comma_changes_line,
                                                          haml_indentation)
    end

    def add_line(code, node, haml_line = node.line, discard_blanks: true)
      return if code.empty? && discard_blanks

      indent_level = @indent_level

      if node.is_a?(HamlLint::Tree::ScriptNode) || node.is_a?(HamlLint::Tree::SilentScriptNode)
        # Since mid-block keywords are children of the corresponding start block
        # keyword, we need to reduce their indentation level by 1. However, we
        # do this only for script node.
        indent_level -= 1 if mid_block_keyword?(code)
      end

      indent = (' ' * 2 * indent_level)

      @source_lines << indent_code(code, indent)

      # For interpolated code in filters that spans multiple lines, the
      # resulting code will span multiple lines, so we need to create a
      # mapping for each line.
      (code.count("\n") + 1).times do
        @line_count += 1
        @source_map[@line_count] = haml_line
      end
    end

    def extract_raw_script(code, first_line_number)
      stripped_code = code.strip
      return if stripped_code.empty?

      line_number = first_line_number - 1
      lines_of_interest = [@original_haml_lines[line_number]]

      while @original_haml_lines[line_number].rstrip.end_with?(',')
        line_number += 1
        lines_of_interest << @original_haml_lines[line_number]
      end

      if lines_of_interest.size == 1
        if lines_of_interest.first.include?(stripped_code)
          return [nil, stripped_code]
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

      line_indents = [match.begin(0)]
      line_indents.concat(raw_ruby.lines[1..-1].map { |l| l.index(/[^ ]/) })
      min_indent = line_indents.min

      # Normally 0, except when multiline code has lines less indented than the first
      required_first_offset = match.begin(0) - min_indent

      [required_first_offset, HamlLint::Utils.indent_lines_after_first(raw_ruby, -min_indent)]
    end

    def indent_code(code, indent)
      codes = code.split("\n")
      codes.map { |c| indent + c }.join("\n")
    end

    def anonymous_block?(text)
      text =~ /\bdo\s*(\|\s*[^\|]*\s*\|)?(\s*#.*)?\z/
    end

    START_BLOCK_KEYWORDS = %w[if unless case begin for until while].freeze
    def start_block_keyword?(text)
      START_BLOCK_KEYWORDS.include?(block_keyword(text))
    end

    MID_BLOCK_KEYWORDS = %w[else elsif when rescue ensure].freeze
    def mid_block_keyword?(text)
      MID_BLOCK_KEYWORDS.include?(block_keyword(text))
    end

    LOOP_KEYWORDS = %w[for until while].freeze
    def block_keyword(text)
      # Need to handle 'for'/'while' since regex stolen from HAML parser doesn't
      if keyword = text[/\A\s*([^\s]+)\s+/, 1]
        return keyword if LOOP_KEYWORDS.include?(keyword)
      end

      return unless keyword = text.scan(Haml::Parser::BLOCK_KEYWORD_REGEX)[0]
      keyword[0] || keyword[1]
    end
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/MethodLength
