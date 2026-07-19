# frozen_string_literal: true

RSpec.describe Workouts::Dedup::FieldElector do
  subject(:elector) { described_class.new }

  describe "#elect" do
    context "with :median rule" do
      it "returns the median value" do
        expect(elector.elect(:distance, [1000, 2000, 3000])).to eq(2000)
      end

      it "returns nil for all nil values" do
        expect(elector.elect(:distance, [nil, nil])).to be_nil
      end
    end

    context "with :mean rule" do
      it "returns the mean value" do
        expect(elector.elect(:average_heartrate, [140, 150, 160])).to eq(150)
      end
    end

    context "with :min rule" do
      it "returns the minimum value" do
        expect(elector.elect(:moving_time, [3600, 1800, 5400])).to eq(1800)
      end
    end

    context "with :max rule" do
      it "returns the maximum value" do
        expect(elector.elect(:elapsed_time, [3600, 7200, 1800])).to eq(7200)
      end
    end

    context "with :non_null rule" do
      it "returns the first non-nil value" do
        result = elector.elect(:average_power, [nil, 200, 250])
        expect(result).to eq(200)
      end
    end

    context "with :best_polyline rule" do
      it "returns the longest polyline" do
        short = "abc"
        long = "abcdefghi"
        result = elector.elect(:summary_polyline, [short, long])
        expect(result).to eq(long)
      end

      it "returns nil for empty strings" do
        expect(elector.elect(:summary_polyline, ["", nil])).to be_nil
      end
    end

    context "with :computed rule" do
      it "returns nil" do
        expect(elector.elect(:average_speed, [3.5, 4.0])).to be_nil
      end
    end

    context "with :best_name rule" do
      it "picks name from highest priority source" do
        values = ["Keep Run", "Garmin Morning", "Strava Jog"]
        sources = %w[keep garmin strava]
        expect(elector.elect(:name, values, sources)).to eq("Garmin Morning")
      end
    end

    context "with :earliest rule" do
      it "returns the earliest date" do
        values = ["2024-06-01T10:00:00Z", "2024-05-01T10:00:00Z"]
        expect(elector.elect(:start_date, values)).to eq("2024-05-01T10:00:00Z")
      end
    end

    context "with unknown field" do
      it "returns first non-nil value" do
        expect(elector.elect(:unknown_field, [1, 2, 3])).to eq(1)
      end
    end
  end
end
