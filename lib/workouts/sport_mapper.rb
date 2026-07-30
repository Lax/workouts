module Workouts
  module SportMapper
    ALIASES = {
      "running" => "run", "trailrun" => "run", "trail_run" => "run",
      "virtualrun" => "run", "virtual_run" => "run",
      "indoorrun" => "run", "indoor_run" => "run",
      "cycling" => "ride", "biking" => "ride",
      "mountainbike" => "ride", "gravelride" => "ride", "ebikeride" => "ride",
      "virtualride" => "ride", "virtual_ride" => "ride",
      "indoor_ride" => "ride", "indoorride" => "ride",
      "hiking" => "hike",
      "walking" => "walk",
      "swimming" => "swim",
      "skiing" => "ski", "backcountryski" => "ski", "nordicski" => "ski",
      "strengthtraining" => "workout"
    }.freeze

    KEYWORDS = [
      [/\b(?:run|jog|sprint|marathon)\w*\b/i, "run"],
      [/\b(?:ride|cycl|bike|mountain\.?bike|gravel|ebike)\w*\b/i, "ride"],
      [/\b(?:hike|climb|mountaineer|trek)\w*\b/i, "hike"],
      [/\b(?:walk|stroll)\w*\b/i, "walk"],
      [/\b(?:swim|pool|laps?)\w*\b/i, "swim"],
      [/\b(?:ski|snowboard|nordic)\w*\b/i, "ski"],
      [/\b(?:workout|train|gym|fitness|yoga|pilates|crossfit|elliptical|strength)\w*\b/i, "workout"]
    ].freeze

    LEV_REFERENCES = %w[
      running run trailrun trail_run virtualrun virtual_run indoorrun indoor_run
      cycling ride biking mountainbike gravelride ebikeride
      virtualride virtual_ride indoor_ride indoorride
      hiking hike walking walk swimming swim skiing ski
      workout strengthtraining training elliptical cardio functional
    ].freeze

    LEV_THRESHOLD = 3

    def self.canonicalize(str)
      return "other" if str.nil? || str.empty?
      key = str.to_s.downcase.strip

      return ALIASES[key] if ALIASES.key?(key)

      KEYWORDS.each { |regex, sport| return sport if regex.match?(str) }

      best = lev_match(key)
      return best if best

      "other"
    end

    def self.lev_match(str)
      best = nil
      best_dist = Float::INFINITY
      LEV_REFERENCES.each do |ref|
        dist = levenshtein(str, ref)
        if dist < best_dist
          best_dist = dist
          best = ref
        end
      end
      return nil if best_dist > LEV_THRESHOLD
      ALIASES[best] || best
    end

    def self.levenshtein(a, b)
      n, m = a.length, b.length
      return m if n == 0
      return n if m == 0
      cur = (0..m).to_a
      (1..n).each do |i|
        prev = cur[0]
        cur[0] = i
        (1..m).each do |j|
          tmp = cur[j]
          cost = (a[i - 1] == b[j - 1]) ? 0 : 1
          cur[j] = [cur[j] + 1, cur[j - 1] + 1, prev + cost].min
          prev = tmp
        end
      end
      cur[m]
    end
  end
end
