require "spec_helper"

RSpec.describe Workouts::StravaCLI do
  let(:cli) { described_class.new }
  let(:fixtures_dir) { File.join(__dir__, "..", "fixtures", "strava") }

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

  describe "#valid_format?" do
    it "accepts non-standard FIT with .FIT signature (real fixture A)" do
      content = File.binread(File.join(fixtures_dir, "nonstandard_header_a.fit"))
      expect(cli.send(:valid_format?, content, :fit, :original)).to be true
    end

    it "accepts non-standard FIT with .FIT signature (real fixture B)" do
      content = File.binread(File.join(fixtures_dir, "nonstandard_header_b.fit"))
      expect(cli.send(:valid_format?, content, :fit, :original)).to be true
    end

    it "accepts standard FIT magic bytes" do
      content = File.binread(File.join(fixtures_dir, "standard_header.fit"))
      expect(cli.send(:valid_format?, content, :fit, :original)).to be true
    end

    it "rejects binary without FIT signature" do
      expect(cli.send(:valid_format?, "\xFF\xFEgarbage", :fit, :original)).to be false
    end
  end

  describe "#fetch — 404 handling" do
    it "skips 404 activities with yellow message instead of failing" do
      client = instance_double(StravaWebLib::Client)
      allow(StravaWebLib::Client).to receive(:new).and_return(client)
      allow(client).to receive(:persist_cookies!)
      allow(client).to receive(:export).with("123", format: :original).and_raise(StravaWebLib::NotFoundError, "HTTP 404 for activity 123")

      tmpdir = Dir.mktmpdir
      cli_with_opts = described_class.new(
        [],
        jwt: "fake-jwt",
        format: "original",
        output: File.join(tmpdir, "raw"),
        db: "/dev/null"
      )

      expect { cli_with_opts.fetch("123") }.to output(/skip 123: no original file on Strava \(HTTP 404\)/).to_stdout
    ensure
      FileUtils.rm_rf(tmpdir) if tmpdir
    end
  end

  describe "#fetch — token_errors count" do
    it "does not print TOKEN_HELP for format mismatch (no token_errors)" do
      client = instance_double(StravaWebLib::Client)
      allow(StravaWebLib::Client).to receive(:new).and_return(client)
      allow(client).to receive(:persist_cookies!)
      allow(client).to receive(:export).and_return(
        StravaWebLib::ExportResult.new(filename: "bad.fit", content: "not-fit", format: :fit)
      )

      tmpdir = Dir.mktmpdir
      cli_with_opts = described_class.new(
        [],
        jwt: "fake-jwt",
        format: "original",
        output: File.join(tmpdir, "raw"),
        db: "/dev/null"
      )
      expect { cli_with_opts.fetch("999") }.not_to output(/Token expired or invalid/).to_stdout
    ensure
      FileUtils.rm_rf(tmpdir) if tmpdir
    end
  end
end
