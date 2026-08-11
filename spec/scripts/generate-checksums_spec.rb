# frozen_string_literal: true

RSpec.describe "scripts/generate-checksums.sh" do
  let(:script) { File.expand_path("../../scripts/generate-checksums.sh", __dir__) }

  around do |example|
    Dir.mktmpdir do |tmp|
      @tmp = tmp
      Dir.chdir(tmp, &example)
    end
  end

  describe "with a directory" do
    before do
      FileUtils.mkdir_p("data/raw/test")
      File.write("data/raw/test/a.fit", "content1")
      File.write("data/raw/test/b.fit", "content2")
    end

    it "generates SHA256SUMS inside the directory that passes verification" do
      `bash #{script} data/raw/test 2>&1`
      expect($?).to be_success
      expect(File).to exist("data/raw/test/SHA256SUMS")
      system("cd data/raw/test && sha256sum -c SHA256SUMS --quiet 2>&1")
      expect($?).to be_success
    end

    it "excludes existing SHA256SUMS from content" do
      File.write("data/raw/test/SHA256SUMS", "dummy hash")
      `bash #{script} data/raw/test`
      content = File.read("data/raw/test/SHA256SUMS")
      expect(content).to include("a.fit")
      expect(content).to include("b.fit")
      expect(content).not_to include("SHA256SUMS")
    end

    it "excludes .modified-at marker from content" do
      File.write("data/raw/test/.modified-at", "stale marker")
      `bash #{script} data/raw/test`
      content = File.read("data/raw/test/SHA256SUMS")
      expect(content).to include("a.fit")
      expect(content).to include("b.fit")
      expect(content).not_to include(".modified-at")
    end
  end

  describe "with a single file" do
    before do
      File.write("test.db", "database content")
    end

    it "generates test.db.SHA256SUMS with matching hash" do
      `bash #{script} test.db 2>&1`
      expect($?).to be_success
      expect(File).to exist("test.db.SHA256SUMS")
      system("sha256sum -c test.db.SHA256SUMS --quiet 2>&1")
      expect($?).to be_success
    end

    it "excludes existing .SHA256SUMS sibling files from content" do
      File.write("other.SHA256SUMS", "dummy")
      `bash #{script} test.db`
      content = File.read("test.db.SHA256SUMS")
      expect(content).to include("test.db")
      expect(content).not_to include("other.SHA256SUMS")
    end
  end

  describe "with multiple arguments" do
    before do
      FileUtils.mkdir_p("data/raw/multi")
      File.write("data/raw/multi/a.fit", "aaa")
      File.write("data/raw/multi/b.fit", "bbb")
      File.write("single.db", "ccc")
    end

    it "generates checksums for each argument" do
      `bash #{script} data/raw/multi single.db 2>&1`
      expect(File).to exist("data/raw/multi/SHA256SUMS")
      expect(File).to exist("single.db.SHA256SUMS")
    end
  end

  describe "nonexistent path" do
    it "silently skips" do
      `bash #{script} nonexistent 2>&1`
      expect($?).to be_success
    end
  end
end
