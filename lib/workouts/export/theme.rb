module Workouts
  module Export
    Theme = Struct.new(:name, :svg, :dashboard, :categories, :map, keyword_init: true)

    module BuiltinThemes
      DARK = Theme.new(
        name: "dark",
        svg: Defaults::SVG,
        dashboard: Defaults::DASHBOARD,
        categories: Defaults::CATEGORIES,
        map: Defaults::MAP,
      ).freeze

      LIGHT = Theme.new(
        name: "light",
        svg: {
          background: "#FFFFFF",
          text: "#222222",
          track: "#4DD2FF",
          track2: "#4DD2FF",
          special: "#FF6B6B",
          special2: "#FF6B6B",
          empty_cell: "#E5E5E5",
          dim_past: "#D4D4D4",
          font: "Arial",
        }.freeze,
        dashboard: {
          background: "#FAFAFA",
          surface: "#FFFFFF",
          hover: "#F0F9FF",
          active_row: "#e0f2fe",
          border: "#E5E5E5",
          text: "#1A1A1A",
          text_secondary: "#64748B",
          text_dim: "#94A3B8",
          text_insight: "#94A3B8",
          accent: "#4DD2FF",
          font: "-apple-system, BlinkMacSystemFont, sans-serif",
        }.freeze,
        categories: Defaults::CATEGORIES,
        map: {
          tiles_dark: Defaults::MAP[:tiles_light],
          tiles_light: Defaults::MAP[:tiles_light],
          echarts_theme: "dark",
        }.freeze,
      ).freeze

      def self.load(name, config: nil)
        name = (name || config&.dig("export", "theme") || "dark").to_s
        case name
        when "dark" then DARK
        when "light" then LIGHT
        else raise ArgumentError, "Unknown theme: #{name}"
        end
      end
    end
  end
end
