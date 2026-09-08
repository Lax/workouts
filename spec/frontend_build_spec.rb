# frozen_string_literal: true

require "json"

RSpec.describe "frontend build dependencies" do
  let(:package) { JSON.parse(File.read(File.expand_path("../package.json", __dir__))) }
  let(:lock_packages) { JSON.parse(File.read(File.expand_path("../package-lock.json", __dir__))).fetch("packages") }

  it "uses web-build 0.0.6 with publicDir and template support" do
    expect(package.dig("dependencies", "@lax/web-build")).to eq("~0.0.6")
    expect(lock_packages.dig("node_modules/@lax/web-build", "version")).to eq("0.0.6")
  end
end
