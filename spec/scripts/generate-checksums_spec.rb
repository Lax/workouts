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

    it "generates test.db.checksum with matching hash" do
      out = `bash #{script} test.db 2>&1`
      expect($?).to be_success
      expect(File).to exist("test.db.checksum")
      system("sha256sum -c test.db.checksum --quiet 2>&1")
      expect($?).to be_success
    end

    it "excludes existing .checksum files from content" do
      File.write("other.checksum", "dummy")
      `bash #{script} test.db`
      content = File.read("test.db.checksum")
      expect(content).to include("test.db")
      expect(content).not_to include("other.checksum")
    end
  end

  describe "with a directory" do
    before do
      FileUtils.mkdir_p("data/raw/test")
      File.write("data/raw/test/a.fit", "content1")
      File.write("data/raw/test/b.fit", "content2")
    end

    it "generates data/raw/test.checksum with all files" do
      `bash #{script} data/raw/test 2>&1`
      expect(File).to exist("data/raw/test.checksum")
      content = File.read("data/raw/test.checksum")
      expect(content).to include("data/raw/test/a.fit")
      expect(content).to include("data/raw/test/b.fit")
    end

    it "excludes .checksum files inside directory" do
      File.write("data/raw/test/.checksum", "fake")
      `bash #{script} data/raw/test`
      content = File.read("data/raw/test.checksum")
      expect(content).not_to include(".checksum")
    end
  end

  describe "with multiple arguments" do
    before do
      File.write("a.db", "aaa")
      File.write("b.db", "bbb")
    end

    it "generates checksums for each" do
      `bash #{script} a.db b.db`
      expect(File).to exist("a.db.checksum")
      expect(File).to exist("b.db.checksum")
    end
  end

  describe "nonexistent path" do
    it "silently skips" do
      out = `bash #{script} nonexistent 2>&1`
      expect($?).to be_success
    end
  end
end
