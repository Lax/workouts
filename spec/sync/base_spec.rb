class TestSyncAdapter < Workouts::Sync::Base
  def call; 0; end
end

RSpec.describe Workouts::Sync::Base do
  subject(:adapter) { TestSyncAdapter.new(config: {}, db: nil, activity_filter:, time_budget:) }
  let(:activity_filter) { nil }
  let(:time_budget) { nil }

  describe "#skip_progress?" do
    subject { adapter.send(:skip_progress?, count, total) }
    let(:total) { nil }

    context "when count ≤ 50" do
      let(:count) { 50 }
      it { is_expected.to be false }
    end

    context "when count 51, remaining > 50" do
      let(:count) { 51 }
      let(:total) { 200 }
      it { is_expected.to be true }
    end

    context "when count 100, total 101 (remaining ≤ 50)" do
      let(:count) { 100 }
      let(:total) { 101 }
      it { is_expected.to be false }
    end

    context "when count 101, remaining > 100 (not divisible by 10)" do
      let(:count) { 101 }
      let(:total) { 300 }
      it { is_expected.to be true }
    end

    context "when count 110, remaining > 100 (divisible by 10)" do
      let(:count) { 110 }
      let(:total) { 300 }
      it { is_expected.to be false }
    end

    context "when count 57, remaining > 50 (not divisible by 5)" do
      let(:count) { 57 }
      let(:total) { 200 }
      it { is_expected.to be true }
    end

    context "when count 55, total 60 (remaining ≤ 50)" do
      let(:count) { 55 }
      let(:total) { 60 }
      it { is_expected.to be false }
    end

    context "when count 60, remaining > 50 (divisible by 5)" do
      let(:count) { 60 }
      let(:total) { 200 }
      it { is_expected.to be false }
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
