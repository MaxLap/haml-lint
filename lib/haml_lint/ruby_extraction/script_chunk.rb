# frozen_string_literal: true

module HamlLint::RubyExtraction
  class ScriptChunk < BaseChunk
    def fuse(other)
      return unless other.is_a?(ScriptChunk) || other.is_a?(ImplicitEndChunk)
      return if other.end_marker_indent_level.nil?

      nb_blank_lines_between = other.haml_start_line - haml_start_line - @ruby_lines.size
      blank_lines = nb_blank_lines_between > 0 ? [''] * nb_blank_lines_between : []
      new_lines = @ruby_lines + blank_lines + other.ruby_lines

      ScriptChunk.new(node,
                      new_lines,
                      haml_start_line: haml_start_line,
                      end_marker_indent_level: other.end_marker_indent_level)
    end

    def assemble_in(assembler)
      assembler.add_lines(@ruby_lines)
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      from_ruby_lines = extract_from(initial_ruby_lines)
      to_ruby_lines = extract_from(corrected_ruby_lines)
      to_ruby_lines.reject! { |l| l.strip == 'end' }

      haml_start_line_index = @haml_start_line - 1
      nb_lines = [from_ruby_lines.size, to_ruby_lines.size].max
      first_missing_line_index = nil

      is_continued_line = false
      continued_line_indent_delta = 2

      nb_lines.times do |i|
        from_ruby_line = from_ruby_lines[i]
        to_ruby_line = to_ruby_lines[i]

        if to_ruby_line
          if to_ruby_line !~ /\S/
            # whitespace or empty
            to_haml_line = ''
          elsif is_continued_line
            to_haml_line = HamlLint::Utils.indent(to_ruby_line, continued_line_indent_delta)
          else
            code_start = to_ruby_line.index(/\S/)
            if assembler.script_output_prefix && to_ruby_line[code_start..-1].start_with?(assembler.script_output_prefix)
              to_ruby_line = to_ruby_line.sub(assembler.script_output_prefix, '')
              to_haml_line = "#{to_ruby_line[0...code_start]}= #{to_ruby_line[code_start..-1]}"
              continued_line_indent_delta = 2 - assembler.script_output_prefix.size
            else
              to_haml_line = "#{to_ruby_line[0...code_start]}- #{to_ruby_line[code_start..-1]}"
              continued_line_indent_delta = 2
            end
          end
        end

        if from_ruby_line.nil?
          haml_lines.insert(haml_start_line_index + i, to_haml_line)
        elsif to_ruby_line.nil?
          first_missing_line_index ||= haml_start_line_index + i
          haml_lines.delete_at(first_missing_line_index)
        else
          haml_lines[haml_start_line_index + i] = to_haml_line
        end
        is_continued_line = !!(to_haml_line =~ /,[ \t]*\z/)
      end
    end
  end
end
