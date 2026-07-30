require "json"

module Workouts
  module Export
    class Stats
      def initialize(db:, output:, activity_filter: nil)
        @db = db
        @output = output
        @activity_filter = activity_filter
      end

      def call
        calculator = Analysis::Calculator.new(db: @db, activity_filter: @activity_filter)
        stats = calculator.call
        File.write(@output, ::JSON.pretty_generate(stats))
        stats[:summary][:total_activities] || 0
      end
    end
  end
end
