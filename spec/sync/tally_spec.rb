RSpec.describe Workouts::Sync::Tally do
  describe "#to_s" do
    {
      0    => "零",
      1    => "一",
      5    => "五",
      9    => "九",
      10   => "十",
      11   => "十一",
      12   => "十二",
      19   => "十九",
      20   => "二十",
      21   => "二十一",
      99   => "九十九",
      100  => "一百",
      101  => "一百零一",
      108  => "一百零八",
      110  => "一百一十",
      111  => "一百一十一",
      120  => "一百二十",
      187  => "一百八十七",
      200  => "二百",
      300  => "三百",
      837  => "八百三十七",
      971  => "九百七十一",
      999  => "九百九十九",
      1000 => "一千",
      1001 => "一千零一",
      1010 => "一千零一十",
      1087 => "一千零八十七",
      1100 => "一千一百",
      2000 => "二千",
      8370 => "八千三百七十",
       9999 => "九千九百九十九",
       1008 => "一千零八",
       1020 => "一千零二十",
       1050 => "一千零五十",
       1200 => "一千二百",
       1201 => "一千二百零一",
       1230 => "一千二百三十",
       1234 => "一千二百三十四",
       2048 => "二千零四十八",
       3007 => "三千零七",
       4000 => "四千",
       5010 => "五千零一十",
       6066 => "六千零六十六",
       7077 => "七千零七十七",
       8080 => "八千零八十",
       9090 => "九千零九十",
    }.each do |n, expected|
      it "#{n} → #{expected}" do
        expect(described_class.new(n).to_s).to eq(expected)
      end
    end
  end

  describe "#to_s (fallback)" do
    it "falls back to numeric string for values exceeding 9999" do
      expect(described_class.new(10000).to_s).to eq("10000")
    end

    it "falls back for 99999" do
      expect(described_class.new(99999).to_s).to eq("99999")
    end

    it "falls back for 100000" do
      expect(described_class.new(100000).to_s).to eq("100000")
    end

    it "falls back for very large values" do
      expect(described_class.new(999999).to_s).to eq("999999")
    end
  end

  describe "#add" do
    it "increments by one" do
      tally = described_class.new(5)
      tally.add
      expect(tally.to_s).to eq("六")
    end

    it "increments by custom amount" do
      tally = described_class.new(8)
      tally.add(3)
      expect(tally.to_s).to eq("十一")
    end
  end
end
