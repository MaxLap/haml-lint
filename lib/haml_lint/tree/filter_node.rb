# frozen_string_literal: true

module HamlLint::Tree
  # Represents a filter node which contains arbitrary code.
  class FilterNode < Node
    # The type of code contained in this filter.
    def filter_type
      @value[:name]
    end

    def text
      # Seems HAML strips the starting blank lines... without them, so line numbers become offset
      # and we can't auto-correct those blank lines.

      nb_blank_lines = 0
      nb_blank_lines += 1 while @document.source_lines[line + nb_blank_lines]&.empty?

      "#{"\n" * nb_blank_lines}#{super}"
    end
  end
end
