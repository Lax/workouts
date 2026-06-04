require_relative "base"

module Workouts
  module Sync
    class IGPSPORT < Base
      def call
        return 0 if @config.empty?
        0
      end
    end
  end
end
