RSpec.describe Workouts::Parser::FIT do
  subject(:parser) { described_class.new }

  describe "#call" do
    context "with a valid FIT file" do
      let(:fit_path) { fixture_path("igpsport/fit_sample.50279925.fit") }

      it "parses FIT and returns activities" do
        results = parser.call(fit_path)
        expect(results).to be_an(Array)
      end

      it "sets start_date and start_date_local to same UTC value" do
        results = parser.call(fit_path)
        act = results.first
        expect(act[:start_date]).to match(/T.*Z\z/)
        expect(act[:start_date_local]).to eq(act[:start_date])
      end

      it "computes distance from GPS points" do
        results = parser.call(fit_path)
        act = results.first
        if act
          expect(act[:distance]).to be_a(Float).and be >= 0
        end
      end
    end

    context "with a non-existent file" do
      it "returns empty array" do
        expect(parser.call("/nonexistent.fit")).to eq([])
      end
    end
  end
end
