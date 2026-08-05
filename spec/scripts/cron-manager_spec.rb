# frozen_string_literal: true

require "yaml"

RSpec.describe ".github/actions/cron-manager/action.yml" do
  let(:action_file) { File.expand_path("../../.github/actions/cron-manager/action.yml", __dir__) }

  around do |example|
    Dir.mktmpdir do |tmp|
      @tmp = tmp
      Dir.chdir(tmp, &example)
    end
  end

  def read_step_run
    action = YAML.safe_load_file(action_file)
    step = action.fetch("runs").fetch("steps").find { |s| s["id"] == "read" }
    step.fetch("run")
  end

  describe "Read current cron interval step" do
    it "extracts N from the workflow file cron line" do
      File.write("sync.yml", "- cron: '0 2 */2 * *'\n")
      run = read_step_run.sub("${{ inputs.workflow-file }}", "sync.yml")
      output_file = File.join(@tmp, "output.txt")
      env = {"GITHUB_OUTPUT" => output_file}
      expect(system(env, "bash -c #{run.shellescape}", exception: false)).to be(true)
      expect(File.read(output_file)).to include("N=2")
    end

    it "leaves N empty when no cron line matches" do
      File.write("sync.yml", "- cron: '0 2 * * *'\n")
      run = read_step_run.sub("${{ inputs.workflow-file }}", "sync.yml")
      output_file = File.join(@tmp, "output.txt")
      env = {"GITHUB_OUTPUT" => output_file}
      expect(system(env, "bash -c #{run.shellescape}", exception: false)).to be(true)
      expect(File.read(output_file)).to include("N=")
    end
  end
end
