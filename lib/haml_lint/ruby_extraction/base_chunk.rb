# frozen_string_literal: true

module HamlLint::RubyExtraction
  class BaseChunk
    COMMA_CHANGES_LINES = true

    # @return [HamlLint::Tree::Node] Haml node that this comes from
    attr_reader :node

    # @return [Integer] First line number of the auto-correctable code in the Haml source
    #   Usually same as node.line, but some cases, such as interpolation in a filter will
    #   will be different.
    attr_reader :haml_start_line

    # @return [Integer] Line number of the line marker in the ruby source placed before
    #   this auto-correctable code
    attr_reader :start_marker_line

    # @return [Integer] Line number of the line marker in the ruby source placed after
    #   this auto-correctable code
    attr_reader :end_marker_line

    attr_reader :end_marker_indent_level

    attr_reader :ruby_lines

    def initialize(node, ruby_lines, haml_start_line: node.line, end_marker_indent_level:)
      ruby_lines = [ruby_lines] if ruby_lines.is_a?(String)
      @node = node
      @ruby_lines = ruby_lines
      @haml_start_line = haml_start_line
      @end_marker_indent_level = end_marker_indent_level
    end

    # Returns nil if self and other_chunk cannot be fused, otherwise, return a new chunk
    def fuse(other_chunk)
      nil
    end

    def assemble_in(assembler)
      raise "Implement #assemble_in in #{self.class.name}"
    end

    def transfer_correction(assembler, initial_ruby_lines, corrected_ruby_lines, haml_lines)
      raise "Implement #transfer_correction in #{self.class.name}"
    end

    def extract_from(source_lines)
      cur_start_marker_index = self.class.find_marker_index(source_lines, @start_marker_line)
      return if cur_start_marker_index.nil?

      cur_end_marker_index = self.class.find_marker_index(source_lines, @end_marker_line)
      return if cur_end_marker_index.nil?

      source_lines[(cur_start_marker_index + 1)..(cur_end_marker_index - 1)]
    end

    def full_assemble(assembler)
      start_marker_indent_level = ruby_lines.first[/ */].size / 2
      @start_marker_line = assembler.add_marker(start_marker_indent_level)

      assemble_in(assembler)

      @end_marker_line = assembler.add_marker(@end_marker_indent_level)
    end

    # Finds the line marker in the given source_lines
    def self.find_marker_index(source_lines, line)
      marker = "#{ChunkAssembler::MARKER_PREFIX}#{line}"

      # In the best cases, the line didn't move
      # Using end_with? because indentation may have been added
      return line - 1 if source_lines[line - 1]&.end_with?(marker)

      source_lines.index { |l| l.end_with?(marker) }
    end
  end
end
