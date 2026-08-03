require "spec_helper"

RSpec.describe Workouts::StravaCLI do
  let(:cli) { described_class.new }

  describe "#warn_html_error" do
    it "does not raise Encoding::CompatibilityError on binary content with non-ASCII bytes" do
      binary = "\xFF\xFE<html".b
      expect { cli.send(:warn_html_error, binary, "123") }.not_to raise_error
    end

    it "reports HTML detection with byte length" do
      html = "<html><body>rate limit</body></html>".b
      expect { cli.send(:warn_html_error, html, "456") }.to output(/456/).to_stdout
    end

    it "reports unexpected format with scrubbed sample" do
      binary = "\xFF\xFEgarbage".b
      expect { cli.send(:warn_html_error, binary, "789") }.to output(/789/).to_stdout
    end
  end
end
