# frozen_string_literal: true

module HamlLint::RubyExtraction
  class TagAttributesChunk < BaseChunk
    def initialize(*args, indent_to_remove: , **kwargs)
      super(*args, **kwargs)
      @indent_to_remove = indent_to_remove
    end

    def extract_from(source_lines)
      lines = super

      lines[0] = lines[0].sub(/^\s*/, '').sub(/W+\(/, '') rescue binding.pry
      lines[-1] = lines[-1].sub(/\)\s*\Z/, '')

      if @indent_to_remove
        lines[1..-1] = lines[1..-1].map do |line|
          line.sub(/^ {1,#{@indent_to_remove}}/, '')
        end
      end

      lines
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      from_ruby_lines = extract_from(initial_ruby_lines)
      to_ruby_lines = extract_from(corrected_ruby_lines)

      haml_start_line_index = @haml_start_line - 1
      haml_end_line_index = haml_start_line_index + from_ruby_lines.size

      affected_haml_lines = haml_lines[haml_start_line_index...haml_end_line_index]

      affected_haml = affected_haml_lines.join("\n")
      from_ruby = from_ruby_lines.join("\n")
      to_ruby = to_ruby_lines.join("\n")

      affected_start_index = affected_haml.index(from_ruby)
      affected_end_index = affected_start_index + from_ruby.size
      affected_haml[affected_start_index...affected_end_index] = to_ruby

      haml_lines[haml_start_line_index...haml_end_line_index] = affected_haml.split("\n")
    end
  end
end
