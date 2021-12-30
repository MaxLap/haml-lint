# frozen_string_literal: true

module HamlLint::RubyExtraction
  class TagScriptChunk < BaseChunk
    def assemble_in(assembler)
      assembler.add_lines(@ruby_lines)
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      from_ruby_lines = extract_from(initial_ruby_lines)
      to_ruby_lines = extract_from(corrected_ruby_lines)

      haml_start_line_index = @haml_start_line - 1

      # TODO: add checks that we have commas at the end of each line except the last one

      from_ruby_line = from_ruby_lines.first
      to_ruby_line = to_ruby_lines.first

      first_to_line_indent = to_ruby_line.index(/\S/)

      from_ruby_line = from_ruby_line.sub(assembler.script_output_prefix, '').sub(/^\s+/, '')
      to_ruby_line = to_ruby_line.sub(assembler.script_output_prefix, '').sub(/^\s+/, '')

      affected_start_index = haml_lines[haml_start_line_index].rindex(from_ruby_line)

      haml_lines[haml_start_line_index][affected_start_index..-1] = to_ruby_line

      indent_delta = affected_start_index - assembler.script_output_prefix.size - first_to_line_indent

      (1...to_ruby_lines.size).each do |i|
        to_ruby_lines[i] = HamlLint::Utils.indent(to_ruby_lines[i], indent_delta)
      end

      haml_end_line_index = haml_start_line_index + from_ruby_lines.size

      haml_lines[(haml_start_line_index+1)...haml_end_line_index] = to_ruby_lines[1..-1]
    end
  end
end
