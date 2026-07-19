Sequel.migration do
  up do
    rows = self[:activities].all

    rows.each do |row|
      updates = {}

      # Detect format: ISO 8601 contains "T", naive format does not
      sd = row[:start_date]
      if sd && sd.is_a?(String) && !sd.include?("T")
        t = Time.parse(sd) rescue nil
        if t
          case row[:source]
          when "apple_health"
            # Apple Health stored +0800 local time as naive "2026-06-25 19:49:17"
            # Parse as local (+0800) then convert to UTC ISO 8601
            local_t = Time.parse(sd + " +0800") rescue nil
            updates[:start_date] = local_t.utc.iso8601 if local_t
          else
            # All other sources stored UTC naive "2026-06-25 11:49:17"
            # Parse as UTC then output ISO 8601
            utc_t = Time.parse(sd + " UTC") rescue nil
            updates[:start_date] = utc_t.iso8601 if utc_t
          end
        end
      end

      sdl = row[:start_date_local]
      if sdl && sdl.is_a?(String) && !sdl.include?("T")
        t = Time.parse(sdl) rescue nil
        if t
          case row[:source]
          when "strava", "igpsport"
            # These stores proper local time, preserve as ISO 8601 with offset
            local_t = Time.parse(sdl + " +0800") rescue nil
            updates[:start_date_local] = local_t.iso8601 if local_t
          else
            # Same as start_date (UTC)
            utc_t = Time.parse(sdl + " UTC") rescue nil
            updates[:start_date_local] = utc_t.iso8601 if utc_t
          end
        end
      end

      self[:activities].where(run_id: row[:run_id]).update(updates) unless updates.empty?
    end
  end

  down do
    # One-way migration: cannot automatically revert ISO 8601 → naive
    # because timezone info would be silently lost.
    # To rollback: restore from DB backup or re-import.
  end
end
