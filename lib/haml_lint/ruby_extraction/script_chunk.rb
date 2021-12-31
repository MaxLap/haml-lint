# frozen_string_literal: true

module HamlLint::RubyExtraction
  class ScriptChunk < BaseChunk
    attr_reader :haml_end_line
    attr_reader :must_start_chunk
    attr_reader :skip_line_indexes_in_source_map

    def initialize(*args, haml_end_line: nil, must_start_chunk: false,
                   skip_line_indexes_in_source_map: [], **kwargs)
      super(*args, **kwargs)
      @must_start_chunk = must_start_chunk
      @skip_line_indexes_in_source_map = skip_line_indexes_in_source_map

      haml_end_line ||= haml_start_line + @ruby_lines.size - 1
      @haml_end_line = haml_end_line
    end

    def fuse(other)
      return unless other.is_a?(ScriptChunk) || other.is_a?(ImplicitEndChunk)
      return if other.end_marker_indent_level.nil?
      return if other.is_a?(ScriptChunk) && other.must_start_chunk

      nb_blank_lines_between = other.haml_start_line - haml_start_line - @ruby_lines.size
      blank_lines = nb_blank_lines_between > 0 ? [''] * nb_blank_lines_between : []
      new_lines = @ruby_lines + blank_lines + other.ruby_lines

      haml_end_line = other.is_a?(ScriptChunk) ? other.haml_end_line : self.haml_end_line

      source_map_skips = @skip_line_indexes_in_source_map
      source_map_skips.concat(other.skip_line_indexes_in_source_map.map { |i| i + @ruby_lines.size })
      if other.is_a?(ImplicitEndChunk)
        source_map_skips << @ruby_lines.size
      end
      ScriptChunk.new(node,
                      new_lines,
                      haml_start_line: haml_start_line,
                      haml_end_line: haml_end_line,
                      skip_line_indexes_in_source_map: source_map_skips,
                      end_marker_indent_level: other.end_marker_indent_level)
    end

    def start_marker_indent_level
      indent_level = ruby_lines.first[/ */].size / 2
      indent_level += 1 if ChunkExtractor.mid_block_keyword?(ruby_lines.first)
      indent_level
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      from_ruby_lines = extract_from(initial_ruby_lines)
      to_ruby_lines = extract_from(corrected_ruby_lines)

      from_last_indent = last_indent(from_ruby_lines)
      to_last_indent = last_indent(to_ruby_lines)

      to_ruby_lines.reject! { |l| l.strip == 'end' }

      continued_line_indent_delta = 2

      to_haml_lines = to_ruby_lines.map.with_index do |line, i|
        if line !~ /\S/
          # whitespace or empty lines, we don't want any indentation
          ''
        elsif line_starts_script?(to_ruby_lines, i)
          code_start = line.index(/\S/)
          if line[code_start..-1].start_with?(assembler.script_output_prefix)
            line = line.sub(assembler.script_output_prefix, '')
            continued_line_indent_delta = 2 - assembler.script_output_prefix.size
            "#{line[0...code_start]}= #{line[code_start..-1]}"
          else
            continued_line_indent_delta = 2
            "#{line[0...code_start]}- #{line[code_start..-1]}"
          end
        else
          HamlLint::Utils.indent(line, continued_line_indent_delta)
        end
      end

      haml_start_line_index = @haml_start_line - 1
      haml_end_line_index = @haml_end_line - 1

      haml_lines[haml_start_line_index..haml_end_line_index] = to_haml_lines
      haml_end_line_index = haml_start_line_index + to_haml_lines.size - 1

      assembler.lock_indent(haml_start_line_index..haml_end_line_index)
      assembler.fix_indent_after(haml_end_line_index, from_last_indent, to_last_indent)
    end

    def unfinished_script_line?(lines, line_index)
      !!lines[line_index][/,[ \t]*\z/]
    end

    def line_starts_script?(lines, line_index)
      return true if line_index == 0
      !unfinished_script_line?(lines, line_index - 1)
    end

    def last_indent(lines)
      (lines.size - 1).downto(0).each do |i|
        next unless line_starts_script?(lines, i)
        indent = lines[i] =~ /\S/
        return indent if indent
      end
    end
  end
end
