module Workouts
  module Export
    module SVG
      class BaseDrawer
        attr_reader :poster

        def initialize(poster)
          @poster = poster
        end

        def draw(doc, size, offset)
          raise NotImplementedError
        end

        private

        def color_from_length(length_range, length, special)
          return poster.colors[:special] if special

          poster.colors[:track]
        end

        def interpolate_color(c1, c2, t)
          r1, g1, b1 = hex_to_rgb(c1)
          r2, g2, b2 = hex_to_rgb(c2)
          r = (r1 + (r2 - r1) * t).round
          g = (g1 + (g2 - g1) * t).round
          b = (b1 + (b2 - b1) * t).round
          rgb_to_hex([r, g, b])
        end

        def hex_to_rgb(h)
          h = h.delete("#")
          [h[0..1].to_i(16), h[2..3].to_i(16), h[4..5].to_i(16)]
        end

        def rgb_to_hex(rgb)
          format("#%02x%02x%02x", *rgb)
        end

        def tag(name, attrs = {}, content = nil)
          attr_str = attrs.map { |k, v| %( #{k}="#{escape(v)}") }.join
          if content
            "<#{name}#{attr_str}>#{content}</#{name}>"
          else
            "<#{name}#{attr_str} />"
          end
        end

        def escape(str)
          str.to_s
             .gsub("&", "&amp;")
             .gsub("<", "&lt;")
             .gsub(">", "&gt;")
             .gsub('"', "&quot;")
        end
      end
    end
  end
end
