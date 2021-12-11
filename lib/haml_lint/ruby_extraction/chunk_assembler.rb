# frozen_string_literal: true

module HamlLint::RubyExtraction
  class ChunkAssembler
    MARKER_PREFIX = 'haml_lint_marker_'

    attr_reader :script_output_prefix

    def initialize(document, ruby_chunks, script_output_prefix:)
      @document = document
      @ruby_chunks = ruby_chunks
      @ruby_lines = []
      @source_map = {}
      @indent_level = 0
      @script_output_prefix = script_output_prefix
    end

    def ruby_source
      return @ruby_source if @ruby_source

      preprocess_chunks

      @ruby_lines = []
      @ruby_chunks.each do |ruby_chunk|
        ruby_chunk.full_assemble(self)
      end

      # Making sure the generated source has a final newline
      @ruby_lines << '' unless @ruby_lines.last.empty?

      @ruby_source = RubySource.new(@ruby_lines.join("\n"), @source_map, @ruby_chunks)
    end

    def preprocess_chunks
      new_chunks = []
      @ruby_chunks.each do |ruby_chunk|
        if new_chunks.empty?
          new_chunks << ruby_chunk
        else
          fused_chunk = new_chunks.last.fuse(ruby_chunk)
          if fused_chunk
            new_chunks[-1] = fused_chunk
          else
            new_chunks << ruby_chunk
          end
        end
      end
      @ruby_chunks = new_chunks
    end

    # Returns a new haml source which had the compatible fixes from corrected_source
    def haml_lines_with_corrections(haml_lines, corrected_ruby_source)
      corrected_ruby_lines = corrected_ruby_source.split("\n")
      finished_with_empty_line = haml_lines.last.empty?

      haml_lines = haml_lines.dup

      # Going in reverse order, so that if we change the number of lines then the
      # rest of the file will not be offset, which would make things harder
      @ruby_chunks.reverse_each do |ruby_chunk|
        ruby_chunk.transfer_correction(self, @ruby_lines, corrected_ruby_lines, haml_lines)
      end

      if finished_with_empty_line && !haml_lines.last.empty?
        haml_lines << ''
      end
      haml_lines
    end

    def add_code(code)
      add_lines(code.split("\n"))
    end

    def add_lines(lines)
      # TODO source_map
      @ruby_lines.concat(lines)
    end

    def line_count
      @ruby_lines.size
    end

    def add_marker(indent_level)
      add_lines(["#{'  ' * indent_level}#{MARKER_PREFIX}#{@ruby_lines.size + 1}"])
      line_count
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
