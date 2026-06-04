module Workouts
  module Export
    module SVG
      class Poster
        attr_accessor :title, :athlete, :tracks, :colors, :special_distance,
                      :width, :height, :drawer_type, :github_style

        def initialize(title, athlete, colors, special_distance)
          @title = title
          @athlete = athlete
          @tracks = []
          @colors = colors
          @special_distance = special_distance
          @width = 200
          @height = 300
          @drawer_type = "title"
          @github_style = "align-firstday"
        end

        def m2u(meters)
          meters * 0.001
        end

        def u
          "km"
        end

        def format_distance(d)
          format("%.1f", m2u(d)) + " " + u
        end
      end
    end
  end
end
