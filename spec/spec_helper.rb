# frozen_string_literal: true

require "yaml"

module WorkflowLoader
  def workflow_path(name)
    File.expand_path("../.github/workflows/#{name}", __dir__)
  end

  def load_workflow(name)
    YAML.safe_load_file(workflow_path(name))
  end

  def workflow_on(yaml)
    yaml.key?(true) ? yaml[true] : yaml["on"]
  end
end

RSpec.configure do |config|
  config.include WorkflowLoader

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.order = :random
  Kernel.srand config.seed
end
