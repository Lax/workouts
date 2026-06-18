require "spec_helper"
require "open3"
require "tmpdir"

RSpec.describe "scripts/source-digest.sh" do
  let(:script) { File.expand_path("../../scripts/source-digest.sh", __dir__) }
  let(:workdir) { Dir.mktmpdir }
  let(:raw_dir) { File.join(workdir, "data", "raw", "test_src") }
  let(:std_dir) { File.join(workdir, "data", "std", "test_src") }

  around do |ex|
    Dir.chdir(workdir) { ex.run }
  ensure
    FileUtils.rm_rf(workdir)
  end

  def run_script(*args)
    stdout, stderr, status = Open3.capture3(script, *args)
    [stdout.strip, stderr.strip, status.exitstatus]
  end

  def create_file(dir, name, content = "hello")
    FileUtils.mkdir_p(dir)
    File.write(File.join(dir, name), content)
  end

  describe "compute mode (no before arg)" do
    let(:empty_digest) { "d41d8cd98f00b204e9800998ecf8427e" }

    it "returns empty-input hash for empty source" do
      out, _, status = run_script("test_src")
      expect(status).to eq(0)
      expect(out).to eq(empty_digest)
    end

    it "returns same hash for same content" do
      create_file(raw_dir, "a.fit", "data1")
      create_file(std_dir, "a.json", '{"lat":1}')
      h1, _, _ = run_script("test_src")
      h2, _, _ = run_script("test_src")
      expect(h1).to eq(h2)
      expect(h1).not_to eq("none")
    end

    it "returns different hash when content changes" do
      create_file(raw_dir, "a.fit", "data1")
      h1, _, _ = run_script("test_src")
      File.write(File.join(raw_dir, "a.fit"), "data2")
      h2, _, _ = run_script("test_src")
      expect(h1).not_to eq(h2)
    end

    it "incorporates both raw and std files" do
      create_file(raw_dir, "a.fit", "data1")
      h1, _, _ = run_script("test_src")
      create_file(std_dir, "a.json", '{"lat":1}')
      h2, _, _ = run_script("test_src")
      expect(h1).not_to eq(h2)
    end

    it "handles directories not existing" do
      out, _, status = run_script("nonexistent")
      expect(status).to eq(0)
      expect(out).to eq(empty_digest)
    end
  end

  describe "check mode (with before arg)" do
    let(:empty_digest) { "d41d8cd98f00b204e9800998ecf8427e" }
    it "returns changed=false when digest matches" do
      create_file(raw_dir, "a.fit", "same")
      digest, _, _ = run_script("test_src")
      out, _, status = run_script("test_src", digest)
      expect(status).to eq(0)
      expect(out).to eq("changed=false")
    end

    it "returns changed=true when digest differs" do
      create_file(raw_dir, "a.fit", "before")
      digest, _, _ = run_script("test_src")
      File.write(File.join(raw_dir, "a.fit"), "after")
      out, _, _ = run_script("test_src", digest)
      expect(out).to eq("changed=true")
    end

    it "returns changed=true when files added" do
      create_file(raw_dir, "a.fit", "data")
      digest, _, _ = run_script("test_src")
      create_file(raw_dir, "b.fit", "more")
      out, _, _ = run_script("test_src", digest)
      expect(out).to eq("changed=true")
    end

    it "returns changed=true when files removed" do
      create_file(raw_dir, "a.fit", "data")
      create_file(std_dir, "a.json", '{"lat":1}')
      digest, _, _ = run_script("test_src")
      FileUtils.rm_f(File.join(std_dir, "a.json"))
      out, _, _ = run_script("test_src", digest)
      expect(out).to eq("changed=true")
    end

    it "returns changed=false when both before and current are empty" do
      out, _, _ = run_script("test_src", empty_digest)
      expect(out).to eq("changed=false")
    end
  end
end
