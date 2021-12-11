# frozen_string_literal: true

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

    def visit_script(node) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      lines = raw_lines_of_interest(node.line)
      lines[0] = lines[0].sub(/(=[ \t]*)/, '')

      raw_code = lines.join("\n")
      start_block = anonymous_block?(raw_code) || start_block_keyword?(raw_code)

      lines[0] = HamlLint::Utils.insert_after_indentation(lines[0], script_output_prefix)

      indent_delta = script_output_prefix.size - $1.size
      (1...lines.size).each do |i|
        lines[i] = HamlLint::Utils.indent(lines[i], indent_delta)
      end

      if start_block
        increment_indent
      end

      @ruby_chunks << ScriptChunk.new(node, lines, end_marker_indent_level: @indent_level)

      yield

      if start_block
        decrement_indent
        @ruby_chunks << ImplicitEndChunk.new(node, ["#{'  ' * @indent_level}end"],
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
      start_block = anonymous_block?(code) || start_block_keyword?(code)

      if start_block
        increment_indent
      end

      @ruby_chunks << ScriptChunk.new(node, lines, end_marker_indent_level: @indent_level)

      yield

      if start_block
        decrement_indent
        @ruby_chunks << ImplicitEndChunk.new(node, ["#{'  ' * @indent_level}end"],
                                             end_marker_indent_level: @indent_level)
      end
    end

    def visit_tag(node)
      @ruby_chunks << TagIndentingChunk.new(node, ["#{'  ' * @indent_level}if haml_lint_tag_indent"],
                                            end_marker_indent_level: nil)

      increment_indent
      yield
      decrement_indent

      @ruby_chunks << ImplicitEndChunk.new(node, ["#{'  ' * @indent_level}end"],
                                           end_marker_indent_level: nil)
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
        add_dummy_puts(node, ":#{node.filter_type}")
        HamlLint::Utils.extract_interpolated_values(node.text) do |interpolated_code, line|
          add_autocorrectable_line(interpolated_code, node, node.line + line)
        end
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
    def raw_ruby_from_haml(code, first_line_number)
      stripped_code = code.strip
      return if stripped_code.empty?

      lines_of_interest = raw_lines_of_interest(first_line_number)

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
