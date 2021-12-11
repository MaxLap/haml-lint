# frozen_string_literal: true

module HamlLint::RubyExtraction
  class ImplicitEndChunk < BaseChunk
    def full_assemble(assembler)
      assembler.add_lines(@ruby_lines)
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
    end
  end
end
