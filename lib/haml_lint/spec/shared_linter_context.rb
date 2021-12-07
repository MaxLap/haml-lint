# frozen_string_literal: true

# Makes writing tests for linters a lot DRYer by taking any currently `haml`
# variable defined via `let` and normalizing it and running the linter against
# it, allowing specs to simply specify whether a lint was reported.

module HamlLint
  module Spec
    module SharedLinterContext
      RSpec.shared_context 'linter' do |autocorrect: nil|
        let(:options) do
          {
            config: HamlLint::ConfigurationLoader.default_configuration,
          }
        end

        let(:config) { options[:config].for_linter(described_class) }

        let(:document) { HamlLint::Document.new(normalize_indent(haml), options) }

        subject { described_class.new(config) }

        before { subject.run(document, autocorrect: autocorrect) }
      end
    end
  end
end
