class TestSyncAdapter < Workouts::Sync::Base
  def call; 0; end
end

RSpec.describe Workouts::Sync::Base do
  subject(:adapter) { TestSyncAdapter.new(config: {}, db: nil, activity_filter:, time_budget:) }
  let(:activity_filter) { nil }
  let(:time_budget) { nil }

  describe "#show_progress?" do
    subject { adapter.send(:show_progress?, count, total) }
    let(:total) { nil }

    context "when count is 1" do
      let(:count) { 1 }
      it { is_expected.to be true }
    end

    context "when remaining ≤ 50" do
      let(:count) { 100 }
      let(:total) { 101 }
      it { is_expected.to be true }
    end

    context "when count is on step boundary" do
      let(:total) { 200 }
      # step = max(1, 1.5 * 200^0.4) = 12
      let(:count) { 60 }
      it { is_expected.to be true }
    end

    context "when count is off step boundary" do
      let(:total) { 200 }
      let(:count) { 57 }
      it { is_expected.to be false }
    end

    context "when total is nil (infinite)" do
      let(:count) { 50 }
      it { is_expected.to be true }
    end
  end

  describe "#time_expired?" do
    subject { adapter.send(:time_expired?) }

    context "when time_budget is nil" do
      it { is_expected.to be false }
    end

    context "when time_budget is 0" do
      let(:time_budget) { 0 }
      it { is_expected.to be false }
    end

    context "when time_budget is positive and not yet expired" do
      let(:time_budget) { 60 }
      before { adapter.instance_variable_set(:@start_time, Time.now) }
      it { is_expected.to be false }
    end

    context "when time_budget is positive and expired" do
      let(:time_budget) { 1 }
      before { adapter.instance_variable_set(:@start_time, Time.now - 10) }
      it { is_expected.to be true }
    end
  end

  describe "#skip_type?" do
    subject { adapter.send(:skip_type?, "run") }

    context "when no activity_filter" do
      it { is_expected.to be false }
    end

    context "when filter includes the type" do
      let(:activity_filter) { %w[run ride] }
      it { is_expected.to be false }
    end

    context "when filter does not include the type" do
      let(:activity_filter) { %w[ride] }
      it { is_expected.to be true }
    end
  end

  describe "#source_label" do
    subject { adapter.send(:source_label) }
    it { is_expected.to eq("TestSyncAdapter") }
  end
end
