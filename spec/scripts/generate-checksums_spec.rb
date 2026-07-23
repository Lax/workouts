# frozen_string_literal: true

RSpec.describe "scripts/generate-checksums.sh" do
  let(:script) { File.expand_path("../../scripts/generate-checksums.sh", __dir__) }

  around do |example|
    Dir.mktmpdir do |tmp|
      @tmp = tmp
      Dir.chdir(tmp, &example)
    end
  end

  describe "with a single file" do
    before do
      File.write("test.db", "database content")
    end

    it "generates test.db.SHA256SUMS with matching hash" do
      expect(system("bash #{script} test.db 2>&1")).to be true
      expect(File).to exist("test.db.SHA256SUMS")
      expect(system("sha256sum -c test.db.SHA256SUMS --quiet 2>&1")).to be true
    end

    it "uses short filename in checksum file" do
      `bash #{script} test.db`
      content = File.read("test.db.SHA256SUMS")
      expect(content).to match(/^\h{64}  test\.db$/)
    end
  end

  describe "with a directory" do
    before do
      FileUtils.mkdir_p("data/raw/test")
      File.write("data/raw/test/a.fit", "content1")
      File.write("data/raw/test/b.fit", "content2")
    end

    it "generates SHA256SUMS inside the directory" do
      `bash #{script} data/raw/test 2>&1`
      expect(File).to exist("data/raw/test/SHA256SUMS")
    end

    it "uses short filenames in checksum content" do
      `bash #{script} data/raw/test`
      content = File.read("data/raw/test/SHA256SUMS")
      expect(content).to include("a.fit")
      expect(content).to include("b.fit")
      expect(content).not_to include("data/raw/test/a.fit")
    end

    it "excludes SHA256SUMS from its own content" do
      File.write("data/raw/test/SHA256SUMS", "stale")
      `bash #{script} data/raw/test`
      content = File.read("data/raw/test/SHA256SUMS")
      expect(content).not_to include("SHA256SUMS")
    end

    it "passes sha256sum --check" do
      `bash #{script} data/raw/test`
      expect(system("cd data/raw/test && sha256sum -c SHA256SUMS --quiet 2>&1")).to be true
    end
  end

  describe "with multiple arguments" do
    before do
      File.write("a.db", "aaa")
      FileUtils.mkdir_p("dir")
      File.write("dir/x", "xxx")
    end

    it "generates checksums for each" do
      `bash #{script} a.db dir`
      expect(File).to exist("a.db.SHA256SUMS")
      expect(File).to exist("dir/SHA256SUMS")
    end
  end

  describe "nonexistent path" do
    it "silently skips" do
      expect(system("bash #{script} nonexistent 2>&1")).to be true
    end
  end
end
