module Workouts
  module Sync
    class Tally
      DIGITS = %w[零 一 二 三 四 五 六 七 八 九 十]

      def initialize(count = 0)
        @count = count
      end

      def add(n = 1)
        @count += n
      end

      def to_s
        return @count.to_s if @count > 9999
        chinese_numeral
      rescue StandardError
        @count.to_s
      end

      private

      def chinese_numeral
        n = @count
        return DIGITS[0] if n == 0
        return DIGITS[n] if n <= 10

        result = ""
        thousands = n / 1000
        n %= 1000
        result += DIGITS[thousands] + "千" if thousands > 0

        hundreds = n / 100
        n %= 100
        if hundreds > 0
          result += DIGITS[hundreds] + "百"
        elsif thousands > 0 && n > 0
          result += "零"
        end

        tens = n / 10
        ones = n % 10
        if tens > 0
          join_ten = tens > 1 || !result.empty?
          result += (join_ten ? DIGITS[tens] : "") + "十"
        elsif !result.empty? && tens == 0 && ones > 0 && !result.end_with?("零")
          result += "零"
        end

        result += DIGITS[ones] if ones > 0
        result
      end
    end
  end
end
