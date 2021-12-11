# frozen_string_literal: true

describe HamlLint::Linter::RuboCop2 do
  context 'autocorrect testing' do
    # The goal is not to test rubocop the gem, so no need to test the details using both
    # :safe and :all
    include_context 'linter', autocorrect: :all

    # steps_string is string of multiple lines describing the steps that
    # the code will take:
    # 1) input haml
    # 2) extracted ruby
    # 3) the corrected ruby
    # 4) the corrected haml
    # Each steps is delimited by a line with ---
    def follows_steps
      step_parts = steps.split(/[ \t]*---[ \t]*\n/)
      raise "Expected 4 steps, got: #{step_parts.size}" if step_parts.size != 4
      start_haml, start_ruby, end_ruby, end_haml = step_parts

      syntax_lints = subject.lints.select { |lint| lint.message =~ %r{Lint/Syntax} }
      syntax_lints = syntax_lints.map { |lint| "#{lint.line}:#{lint.message}" }

      subject.last_extracted_source.source.should == start_ruby

      syntax_lints.should(be_empty, "Got Syntax lints:\n#{syntax_lints.join("\n")}")

      subject.last_new_ruby_source.should == end_ruby
      document.source.should == end_haml

      document.source_was_changed.should be (start_haml != end_haml)
    end

    let(:haml) {
      steps.split('---').first
    }

    examples_from(__dir__ + '/rubocop_autocorrect_examples/script_examples.txt').each do |example|
      context "(script_examples.txt:#{example.first_line_no}) #{example.name}" do
        let(:steps) { example.string }

        it { follows_steps }
      end
    end

    examples_from(__dir__ + '/rubocop_autocorrect_examples/ruby_filter_examples.txt').each do |example|
      context "(ruby_filter_examples.txt:#{example.first_line_no}) #{example.name}" do
        let(:steps) { example.string }

        it { follows_steps }
      end
    end
  end
end
