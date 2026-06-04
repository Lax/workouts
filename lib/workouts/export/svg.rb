require_relative "svg/base"
require_relative "svg/poster"
require_relative "svg/track"
require_relative "svg/github"
require_relative "svg/grid"
require_relative "svg/circular"
require_relative "svg/month_of_life"
require_relative "svg/year_summary"

module Workouts
  module Export
    module SVG
      STYLES = %w[github grid circular month-of-life year-summary].freeze
    end
  end
end

require_relative "svg/renderer"
