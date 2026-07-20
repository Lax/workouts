# frozen_string_literal: true

RSpec.describe "scripts/data-store-checksum.sh" do
  let(:script) { File.expand_path("../../scripts/data-store-checksum.sh", __dir__) }

  around do |example|
    Dir.mktmpdir do |tmp|
      @tmp = tmp
      FileUtils.ln_s(File.expand_path("../../data", __dir__), "#{tmp}/data")
      Dir.chdir(tmp, &example)
    end
  end

  describe "with existing .checksum file" do
    before do
      FileUtils.mkdir_p("data/raw/test")
      File.write("data/raw/test/a.fit", "content1")
      File.write("data/raw/test/.checksum", "abc123  data/raw/test/a.fit\n")
    end

    it "outputs a digest based on .checksum content" do
      out = `bash #{script} test`
      expect(out.strip).to match(/\A[0-9a-f]{64}\z/)
      expect($?).to be_success
    end
  end

  describe "without .checksum file" do
    it "outputs 'none'" do
      out = `bash #{script} nonexistent`
      expect(out.strip).to eq("none")
    end
  end
end
