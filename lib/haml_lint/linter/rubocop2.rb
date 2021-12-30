# frozen_string_literal: true

require 'rubocop'
require 'tempfile'

module HamlLint
  # Runs RuboCop on Ruby code contained within HAML templates.
  class Linter::RuboCop2 < Linter # rubocop:disable Metrics/ClassLength
    include LinterRegistry

    SUPPORTS_AUTOCORRECT = true

    # Maps the ::RuboCop::Cop::Severity levels to our own levels.
    SEVERITY_MAP = {
      error: :error,
      fatal: :error,
      convention: :warning,
      refactor: :warning,
      warning: :warning,
    }.freeze

    # Debug fields, also used in tests
    attr_accessor :last_extracted_source
    attr_accessor :last_new_ruby_source

    def visit_root(_node) # rubocop:disable Metrics/AbcSize
      yield :skip_children
      @rubocop_config = self.class.rubocop_config_store.for(document.file, config['sent_to_rubocop'])

      @last_extracted_source = nil
      @last_new_ruby_source = nil

      extractor = HamlLint::RubyExtraction::ChunkExtractor.new(document)
      assembler = extractor.assembler
      extracted_source = assembler.ruby_source
      @last_extracted_source = extracted_source

      if extracted_source.source.empty?
        @last_new_ruby_source = ''
        return
      end

      new_ruby_source = process_ruby_source(extracted_source.source, extracted_source.source_map)
      @last_new_ruby_source = new_ruby_source

      if @autocorrect && new_ruby_source != extracted_source.source
        # Autocorrect did changes, so we must merge them back into the document
        haml_lines = assembler.haml_lines_with_corrections(new_ruby_source)
        document.change_source(haml_lines.join("\n"))
      end
    end

    private

    class RubocopConfigStore
      def initialize
        @dir_to_config_path_cache = {}
        @config_path_to_config_cache = {}
      end

      def config_path_for(path)
        dir = if File.directory?(path)
                path
              else
                File.dirname(path)
              end

        @dir_to_config_path_cache[dir] ||= ::RuboCop::ConfigLoader.configuration_file_for(dir)
      end

      def for(path, template_hash)
        config_path = config_path_for(path)

        @config_path_to_config_cache[config_path] ||= begin
          build_config_with(config_path, template_hash)
        end
      end

      def build_config_with(config_path, template_hash)
        template_hash = template_hash.dup
        template_hash['inherit_from'] = config_path

        Tempfile.create(['.haml-lint-rubocop', '.yml'], Dir.pwd) do |tempfile|
          tempfile.write(template_hash.to_yaml)
          tempfile.close
          ::RuboCop::ConfigLoader.configuration_from_file(tempfile.path)
        end
      end
    end

    # A single CLI instance is shared between files to avoid RuboCop
    # having to repeatedly reload .rubocop.yml.
    def self.rubocop_cli # rubocop:disable Lint/IneffectiveAccessModifier:
      # The ivar is stored on the class singleton rather than the Linter instance
      # because it can't be Marshal.dump'd (as used by Parallel.map)
      @rubocop_cli ||= ::RuboCop::CLI.new
    end

    def self.rubocop_config_store
      @rubocop_config_store = RubocopConfigStore.new
    end

    # Executes RuboCop against the given Ruby code, records the offenses as
    # lints and runs autocorrect if requested.
    #
    # @param ruby [String] Ruby code
    # @param source_map [Hash] map of Ruby code line numbers to original line
    #   numbers in the template
    # @return [String] The autocorrected Ruby source code
    def process_ruby_source(ruby, source_map)
      filename = document.file || 'ruby_script'

      final_ruby = Tempfile.open([File.basename(filename), '.rb']) do |tempfile|
        tempfile.write(ruby)
        tempfile.close
        extract_lints_from_offenses(lint_file(self.class.rubocop_cli, tempfile.path), source_map)
        tempfile.open
        tempfile.read
      end

      final_ruby
    end

    # Defined so we can stub the results in tests
    #
    # @param rubocop [RuboCop::CLI]
    # @param file [String]
    # @return [Array<RuboCop::Cop::Offense>]
    def lint_file(rubocop_cli, file)
      if !ENV['HAML_LINT_RUBOCOP_CONF']
        rubocop_cli.config_store.instance_variable_set(:@options_config, @rubocop_config)
      end

      status = rubocop_cli.run(rubocop_flags << file)
      unless [::RuboCop::CLI::STATUS_SUCCESS, ::RuboCop::CLI::STATUS_OFFENSES].include?(status)
        raise HamlLint::Exceptions::ConfigurationError,
              "RuboCop exited unsuccessfully with status #{status}." \
              ' Check the stack trace to see if there was a misconfiguration.'
      end
      OffenseCollector.offenses
    end

    # Aggregates RuboCop offenses and converts them to {HamlLint::Lint}s
    # suitable for reporting.
    #
    # @param offenses [Array<RuboCop::Cop::Offense>]
    # @param source_map [Hash]
    def extract_lints_from_offenses(offenses, source_map)
      dummy_node = Struct.new(:line)

      offenses.reject { |offense| Array(config['ignored_cops']).include?(offense.cop_name) }
              .each do |offense|
        record_lint(dummy_node.new(source_map[offense.line]), offense.message,
                    offense.severity.name)
      end
    end

    # Record a lint for reporting back to the user.
    #
    # @param node [#line] node to extract the line number from
    # @param message [String] error/warning to display to the user
    # @param severity [Symbol] RuboCop severity level for the offense
    def record_lint(node, message, severity)
      @lints << HamlLint::Lint.new(self, @document.file, node.line, message,
                                   SEVERITY_MAP.fetch(severity, :warning))
    end

    # Returns flags that will be passed to RuboCop CLI.
    #
    # @return [Array<String>]
    def rubocop_flags
      flags = %w[--format HamlLint::OffenseCollector]
      flags += ['--config', ENV['HAML_LINT_RUBOCOP_CONF']] if ENV['HAML_LINT_RUBOCOP_CONF']
      flags += ignored_cops_flags
      flags += rubocop_autocorrect_flags
      flags
    end

    def rubocop_autocorrect_flags # rubocop:disable Metrics/PerceivedComplexity
      return [] unless @autocorrect

      rubocop_version = Gem::Version.new(::RuboCop::Version::STRING)

      if @autocorrect == :safe
        if rubocop_version >= Gem::Version.new('0.87')
          ['--auto-correct']
        else
          msg = "This rubocop version (#{::RuboCop::Version::STRING}) doesn't " \
                'support safe auto-correct. Need at least 0.87'
          raise NotImplementedError, msg
        end
      elsif @autocorrect == :all
        if rubocop_version >= Gem::Version.new('0.87')
          ['--auto-correct-all']
        else
          ['--auto-correct']
        end
      else
        raise "Unexpected autocorrect option: #{@autocorrect.inspect}"
      end
    end

    # Because of autocorrect, we need to pass the ignored cops to RuboCop to
    # prevent it from doing fixes we don't want.
    # Because cop names changed names over time, we cleanup those that don't exist
    # anymore or don't exist yet.
    # This is not exhaustive, it's only for the cops that are in config/default.yml
    def ignored_cops_flags # rubocop:disable Metrics/MethodLength
      ignored_cops = config['ignored_cops']
      rubocop_version = Gem::Version.new(::RuboCop::Version::STRING)
      ignored_cops -= if rubocop_version >= Gem::Version.new('0.53')
                        %w[Lint/BlockAlignment Lint/EndAlignment]
                      else
                        %w[Layout/BlockAlignment Layout/EndAlignment]
                      end

      ignored_cops -= if rubocop_version >= Gem::Version.new('0.77')
                        %w[Layout/AlignHash
                           Layout/AlignParameters
                           Layout/TrailingBlankLines]
                      else
                        %w[Layout/HashAlignment
                           Layout/ParameterAlignment
                           Layout/TrailingEmptyLines]
                      end

      ignored_cops -= if rubocop_version >= Gem::Version.new('0.79')
                        ['Metrics/LineLength']
                      else
                        ['Layout/LineLength']
                      end

      if @autocorrect
        ignored_cops += config['ignored_autocorrect_cops']
        # Running not auto-correctable cops during the auto-correct step is just wasteful and noisy
        if ::RuboCop::Cop::Registry.respond_to?(:all)
          cops_without_autocorrect = ::RuboCop::Cop::Registry.all.reject(&:support_autocorrect?)
          # This cop cannot be disabled
          cops_without_autocorrect.delete(::RuboCop::Cop::Lint::Syntax)
          ignored_cops += cops_without_autocorrect.map { |cop| cop.badge.to_s }
        end
      end
      ['--except', ignored_cops.uniq.join(',')]
    end
  end

  # Collects offenses detected by RuboCop.
  class OffenseCollector < ::RuboCop::Formatter::BaseFormatter
    class << self
      # List of offenses reported by RuboCop.
      attr_accessor :offenses
    end

    # Executed when RuboCop begins linting.
    #
    # @param _target_files [Array<String>]
    def started(_target_files)
      self.class.offenses = []
    end

    # Executed when a file has been scanned by RuboCop, adding the reported
    # offenses to our collection.
    #
    # @param _file [String]
    # @param offenses [Array<RuboCop::Cop::Offense>]
    def file_finished(_file, offenses)
      self.class.offenses += offenses
    end
  end
end
