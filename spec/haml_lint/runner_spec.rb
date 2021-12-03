# frozen_string_literal: true

describe HamlLint::Runner do
  let(:base_options) { { reporter: reporter } }
  let(:options) { base_options }
  let(:reporter) { HamlLint::Reporter::HashReporter.new(StringIO.new) }
  let(:runner) { described_class.new }

  before do
    runner.stub(:extract_applicable_files).and_return(files)
  end

  describe '#run' do
    subject { runner.run(options) }

    context 'general tests' do
      let(:files) { %w[file1.slim file2.slim] }
      let(:mock_linter) { double('linter', lints: [], name: 'Blah') }

      let(:options) do
        base_options.merge(reporter: reporter)
      end

      before do
        runner.stub(:collect_lints).and_return([])
      end

      it 'searches for lints in each file' do
        runner.should_receive(:collect_lints).exactly(files.size).times
        subject
      end

      context 'when :config_file option is specified' do
        let(:options) { base_options.merge(config_file: 'some-config.yml') }
        let(:config) { double('config') }

        it 'loads that specified configuration file' do
          config.stub(:for_linter).and_return('enabled' => true)

          HamlLint::ConfigurationLoader.should_receive(:load_applicable_config)
                                       .with('some-config.yml')
                                       .and_return(config)
          subject
        end
      end

      context 'when :auto_gen_config option is specified' do
        let(:options) { base_options.merge(auto_gen_config: true) }
        let(:config) { double('config') }

        it 'loads that specified configuration file' do
          config.stub(:for_linter).and_return('enabled' => true)

          HamlLint::ConfigurationLoader.should_receive(:load_applicable_config)
                                       .with(nil, exclude_files: [
                                               HamlLint::ConfigurationLoader::AUTO_GENERATED_FILE
                                             ]).and_return(config)
          subject
        end
      end

      context 'when `exclude` global config option specifies a list of patterns' do
        let(:options) { base_options.merge(config: config, files: files) }
        let(:config) { HamlLint::Configuration.new(config_hash) }
        let(:config_hash) { { 'exclude' => 'exclude-this-file.slim' } }

        before do
          runner.stub(:extract_applicable_files).and_call_original
        end

        it 'passes the global exclude patterns to the FileFinder' do
          HamlLint::FileFinder.any_instance
                              .should_receive(:find)
                              .with(files, ['exclude-this-file.slim'])
                              .and_return([])
          subject
        end
      end

      context 'when :parallel option is specified' do
        let(:options) { base_options.merge(parallel: true) }

        it 'warms up the cache in parallel' do
          runner.should_receive(:warm_cache).and_call_original
          subject
        end
      end

      context 'when :autocorrect option' do
        include_context 'isolated environment'

        let(:files) { %w[with_autocorrectable_mistake.haml] }
        let(:initial_haml) { <<~HAML }
          %div
            - foo(bar ,  42)
        HAML
        let(:corrected_haml) { <<~HAML }
          %div
            - foo(bar, 42)
        HAML

        before do
          # The runner needs to actually look for files to lint
          runner.should_receive(:collect_lints).and_call_original
          File.write('with_autocorrectable_mistake.haml', initial_haml)
        end

        context 'is set to :safe' do
          let(:options) { base_options.merge(autocorrect: :safe) }

          it 'writes out the corrected file' do
            if Gem::Version.new(::RuboCop::Version::STRING) >= Gem::Version.new('0.87')
              subject
              File.read('with_autocorrectable_mistake.haml').should == corrected_haml
            else
              expect { subject }.to raise_error(NotImplementedError,
                                                /doesn't support safe auto-correct/)
            end
          end
        end

        context 'is set to :all' do
          let(:options) { base_options.merge(autocorrect: :all) }

          it 'writes out the corrected file' do
            subject
            File.read('with_autocorrectable_mistake.haml').should == corrected_haml
          end
        end

        context 'is not set' do
          it "doesn't write out the corrected file" do
            subject
            File.read('with_autocorrectable_mistake.haml').should == initial_haml
          end
        end
      end

      context 'when there is a Haml parsing error in a file' do
        let(:files) { %w[inconsistent_indentation.haml] }

        include_context 'isolated environment'

        before do
          # The runner needs to actually look for files to lint
          runner.should_receive(:collect_lints).and_call_original
          haml = "%div\n  %span Hello, world\n\t%span Goodnight, moon"

          `echo "#{haml}" > inconsistent_indentation.haml`
        end

        it 'adds a syntax lint to the output' do
          subject.lints.size.should == 1

          lint = subject.lints.first
          lint.line.should == 2
          lint.filename.should == 'inconsistent_indentation.haml'
          lint.message.should match(/Inconsistent indentation/)
          lint.severity.should == :error

          linter = lint.linter
          linter.name.should == 'Syntax'
        end
      end
    end

    context 'integration tests' do
      context 'when the fail-fast option is specified with fail-level' do
        let(:files) { %w[example.haml example2.haml] }
        let(:options) { base_options.merge(fail_fast: fail_fast, fail_level: :error) }

        include_context 'isolated environment'

        before do
          `echo "#my-id Hello\n#my-id World" > example.haml`
          `echo "-# Hello\n-# World" > example2.haml`
        end

        context 'and it is false' do
          let(:fail_fast) { false }

          it 'reports the warning but does not halt on it' do
            subject.lints.size.should == 3
          end
        end

        context 'and it is true' do
          let(:fail_fast) { true }

          it 'reports the warning and halts on it' do
            subject.lints.size.should == 2
          end
        end
      end
    end
  end
end
