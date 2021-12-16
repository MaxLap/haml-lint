# frozen_string_literal: true

module HamlLint::RubyExtraction
  class RubyFilterChunk < BaseChunk
    def assemble_in(assembler)
      assembler.add_lines(@ruby_lines)
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      from_ruby_lines = extract_from(initial_ruby_lines)
      to_ruby_lines = extract_from(corrected_ruby_lines)

      to_haml_lines = to_ruby_lines.map.with_index do |line, i|
        if line !~ /\S/
          # whitespace or empty
          to_haml_line = ''
        else
          to_haml_line = "  #{line}"
        end
      end

      haml_start_line_index = @haml_start_line - 1
      haml_end_line_index = haml_start_line_index + from_ruby_lines.size - 1

      haml_lines[haml_start_line_index..haml_end_line_index] = to_haml_lines
      haml_end_line_index = haml_start_line_index + to_haml_lines.size - 1

      assembler.lock_indent(haml_start_line_index..haml_end_line_index)
    end
  end
end
