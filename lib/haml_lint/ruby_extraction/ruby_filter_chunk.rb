# frozen_string_literal: true

module HamlLint::RubyExtraction
  class RubyFilterChunk < BaseChunk
    def assemble_in(assembler)
      assembler.add_lines(@ruby_lines)
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      from_ruby_lines = extract_from(initial_ruby_lines)
      to_ruby_lines = extract_from(corrected_ruby_lines)

      haml_start_line_index = @haml_start_line - 1
      nb_lines = [from_ruby_lines.size, to_ruby_lines.size].max
      first_missing_line_index = nil

      nb_lines.times do |i|
        from_ruby_line = from_ruby_lines[i]
        to_ruby_line = to_ruby_lines[i]

        if to_ruby_line
          if to_ruby_line !~ /\S/
            # whitespace or empty
            to_haml_line = ''
          else
            to_haml_line = "  #{to_ruby_line}"
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
      end
    end
  end
end
