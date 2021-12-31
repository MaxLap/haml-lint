# frozen_string_literal: true

module HamlLint::RubyExtraction
  class InterpolationChunk < BaseChunk
    def initialize(*args, start_char_index:, **kwargs)
      super(*args, **kwargs)
      @start_char_index = start_char_index
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      from_ruby_lines = extract_from(initial_ruby_lines)
      to_ruby_lines = extract_from(corrected_ruby_lines)

      binding.pry if to_ruby_lines.size > 1
      binding.pry if from_ruby_lines.size > 1

      from_ruby_line = from_ruby_lines.first.sub(assembler.script_output_prefix, '').sub(/^\s+/, '')
      to_ruby_line = to_ruby_lines.first.sub(assembler.script_output_prefix, '').sub(/^\s+/, '')

      haml_start_line_index = @haml_start_line - 1

      haml_line = haml_lines[haml_start_line_index]
      haml_line[@start_char_index...(@start_char_index + from_ruby_line.size)] = to_ruby_line
    end
  end
end
