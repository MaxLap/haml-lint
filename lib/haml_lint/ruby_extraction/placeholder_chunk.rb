# frozen_string_literal: true

module HamlLint::RubyExtraction
  # This chunk just adds its code to the ruby, but does not attempt to transfer their correction.
  # Used so that Rubocop doesn't think that there is nothing in `if` and other stuch structures,
  # so that it does corrections that make sense for the HAML.
  class PlaceholderChunk < BaseChunk
    def wrap_in_markers
      false
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
    end
  end
end
