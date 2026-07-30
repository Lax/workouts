module Workouts
  module Export
    module Defaults
      SVG = {
        background: "#222222",
        text: "#FFFFFF",
        track: "#4DD2FF",
        track2: "#4DD2FF",
        special: "#FFFF00",
        special2: "#FFFF00",
        empty_cell: "#444444",
        dim_past: "#555555",
        font: "Arial"
      }.freeze

      DASHBOARD = {
        background: "#1a1a2e",
        surface: "#16213e",
        hover: "#0f3460",
        active_row: "#1a3a6a",
        border: "#2a2a4a",
        text: "#e0e0e0",
        text_secondary: "#888",
        text_dim: "#666",
        text_insight: "#aaa",
        accent: "#4DD2FF",
        font: "-apple-system, BlinkMacSystemFont, sans-serif"
      }.freeze

      CATEGORIES = {
        "run" => "#4DD2FF",
        "walk" => "#4ECDC4",
        "ride" => "#FF6B6B",
        "hike" => "#FFD93D"
      }.freeze

      MAP = {
        tiles_dark: "https://{s}.basemaps.cartocdn.com/dark_nolabels/{z}/{x}/{y}{r}.png",
        tiles_light: "https://{s}.basemaps.cartocdn.com/light_nolabels/{z}/{x}/{y}{r}.png",
        echarts_theme: "dark"
      }.freeze
    end
  end
end
