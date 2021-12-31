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
      @script_output_prefix = script_output_prefix

      @haml_lines = nil

      # Since we transfer corrections from the end, indexes from
      # the start would become incorrect when line numbers are changed.
      @locked_indent_line_rindexes = []
    end

    def ruby_source
      return @ruby_source if @ruby_source

      preprocess_chunks

      @ruby_lines = []
      @ruby_chunks.each do |ruby_chunk|
        ruby_chunk.full_assemble(self)
      end

      # Making sure the generated source has a final newline
      @ruby_lines << '' if @ruby_lines.last && !@ruby_lines.last.empty?

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
    def haml_lines_with_corrections(corrected_ruby_source)
      corrected_ruby_lines = corrected_ruby_source.split("\n")

      @haml_lines = @document.source_lines.dup
      finished_with_empty_line = @haml_lines.last.empty?

      # Going in reverse order, so that if we change the number of lines then the
      # rest of the file will not be offset, which would make things harder
      @ruby_chunks.reverse_each do |ruby_chunk|
        ruby_chunk.transfer_correction(self, @ruby_lines, corrected_ruby_lines, @haml_lines)
      end

      if finished_with_empty_line && !@haml_lines.last.empty?
        @haml_lines << ''
      end
      @haml_lines
    end

    def add_lines(lines, haml_start_line:, skip_indexes_in_source_map: [])
      nb_skipped_source_map_lines = 0
      lines.size.times do |i|
        if skip_indexes_in_source_map.include?(i)
          nb_skipped_source_map_lines += 1
        end
        @source_map[@ruby_lines.size + i + 1] = haml_start_line + i - nb_skipped_source_map_lines
      end
      @ruby_lines.concat(lines)
    end

    def line_count
      @ruby_lines.size
    end

    def add_marker(indent_level, haml_line:)
      add_lines(["#{'  ' * indent_level}#{MARKER_PREFIX}#{@ruby_lines.size + 1}"], haml_start_line: haml_line)
      line_count
    end

    def lock_indent(line_indexes)
      line_indexes = Array(line_indexes)
      line_indexes.each do |i|
        @locked_indent_line_rindexes[@haml_lines.size - 1 - i] = true
      end
    end

    def line_locked_indent?(line_index)
      @locked_indent_line_rindexes[@haml_lines.size - 1 - line_index]
    end

    def fix_indent_after(after_line_index, from_indent, to_indent)
      return if from_indent == to_indent

      delta_indent = to_indent  - from_indent

      (after_line_index + 1..@haml_lines.size - 1).each do |line_index|
        line = @haml_lines[line_index]
        indent = line.index(/\S/)

        next if indent.nil?
        break if indent <= from_indent
        next if line_locked_indent?(line_index)
        @haml_lines[line_index] = HamlLint::Utils.indent(line, delta_indent)
      end
    end
  end
end
