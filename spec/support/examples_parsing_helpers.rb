# frozen_string_literal: true

# Helpers for parsing examples
module ExamplesParsingHelpers
  module_function

  Example = Struct.new(:name, :string, :first_line_no)

  def examples_from(path)
    string = File.read(path)

    examples_lines = string.lines.slice_before(/\A\s*!!!/)
    next_line_number = 1
    examples = examples_lines.flat_map do |example_lines|
      cur_line_number = next_line_number
      next_line_number += example_lines.size

      title_command = example_lines[0].strip
      # Remove the first example when the file starts with comments
      next unless title_command.start_with?('!!!')

      title = title_command.sub('!!!', '').lstrip
      example_string = example_lines[1..-1].join.strip + "\n"
      example_string = ERB.new(example_string).result

      # Completely remove lines with only a !# comment on them
      example_string = example_string.gsub(/^\s*!#.*\n?/, '')

      # Remove !# comments
      example_string = example_string.gsub(/!#.*/, '')

      if example_string.include?('^')
        silent_example_string = example_string.gsub('^^', '').gsub('^', '-').gsub('%%', '')
        out_example_string = example_string.gsub('^^', 'HL.out = ')
                                           .gsub('%%', '         ')
                                           .gsub('^', '=')
        [
          Example.new("(^ as -)#{title}", silent_example_string, cur_line_number),
          Example.new("(^ as =)#{title}", out_example_string, cur_line_number),
        ]
      else
        Example.new(title, example_string, cur_line_number)
      end
    end

    examples.compact
  end
end
