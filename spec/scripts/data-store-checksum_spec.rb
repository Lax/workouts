# frozen_string_literal: true

RSpec.describe "scripts/data-store-checksum.sh" do
  let(:script) { File.expand_path("../../scripts/data-store-checksum.sh", __dir__) }

  around do |example|
    Dir.mktmpdir do |tmp|
      @tmp = tmp
      Dir.chdir(tmp, &example)
    end
  end

  describe "with existing SHA256SUMS file" do
    before do
      FileUtils.mkdir_p("data/raw/test")
      File.write("data/raw/test/a.fit", "content1")
      File.write("data/raw/test/b.fit", "content2")
      # Simulate generate-checksums.sh output inside directory
      system("cd data/raw/test && sha256sum a.fit b.fit > SHA256SUMS", exception: false)
    end

    it "outputs a digest based on SHA256SUMS content" do
      out = `bash #{script} test`
      expect(out.strip).to match(/\A[0-9a-f]{64}\z/)
      expect($?).to be_success
    end
  end

  describe "without SHA256SUMS file" do
    it "outputs 'none'" do
      out = `bash #{script} nonexistent`
      expect(out.strip).to eq("none")
    end
  end
end
