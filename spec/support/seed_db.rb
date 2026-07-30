require "sequel"

SEED_ACTIVITIES = [
  {
    run_id: "garmin_1", name: "Morning Run", distance: 5_000, moving_time: 1800,
    elapsed_time: 1900, sport_category: "run", sport_type: "running",
    start_date: "2025-01-15T08:00:00Z", start_date_local: "2025-01-15T16:00:00",
    summary_polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
    average_heartrate: 145, max_heartrate: 172,
    average_cadence: 82, max_cadence: 95,
    average_power: nil, max_power: nil,
    calories: 350, average_temperature: 18,
    average_speed: 2.78, elevation_gain: 25,
    source: "garmin"
  },
  {
    run_id: "strava_2", name: "Evening Ride", distance: 20_000, moving_time: 3600,
    elapsed_time: 3800, sport_category: "ride", sport_type: "cycling",
    start_date: "2025-01-14T18:00:00Z", start_date_local: "2025-01-15T02:00:00",
    summary_polyline: "}~p~iF~ps|U_ulLnnqC_mqNvxq`@",
    average_heartrate: 130, max_heartrate: 155,
    average_cadence: 75, max_cadence: 90,
    average_power: 160, max_power: 320,
    calories: 800, average_temperature: 22,
    average_speed: 5.56, elevation_gain: 120,
    source: "strava"
  },
  {
    run_id: "keep_3", name: "Lunch Walk", distance: 3_000, moving_time: 2400,
    elapsed_time: 2500, sport_category: "walk", sport_type: "walking",
    start_date: "2025-01-13T12:30:00Z", start_date_local: "2025-01-13T20:30:00",
    summary_polyline: nil,
    average_heartrate: 95, max_heartrate: 110,
    average_cadence: 55, max_cadence: 65,
    average_power: nil, max_power: nil,
    calories: 120, average_temperature: 15,
    average_speed: 1.25, elevation_gain: 5,
    source: "keep"
  },
  {
    run_id: "garmin_4", name: "Weekend Hike", distance: 12_000, moving_time: 5400,
    elapsed_time: 6000, sport_category: "hike", sport_type: "hiking",
    start_date: "2024-12-28T07:00:00Z", start_date_local: "2024-12-28T15:00:00",
    summary_polyline: "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
    average_heartrate: 120, max_heartrate: 145,
    average_cadence: nil, max_cadence: nil,
    average_power: nil, max_power: nil,
    calories: 600, average_temperature: 10,
    average_speed: 2.22, elevation_gain: 450,
    source: "garmin"
  }
]

def create_seed_db
  db = Sequel.sqlite
  Sequel.extension :migration
  Sequel::Migrator.run(db, File.expand_path("../../db/migrations", __dir__))

  SEED_ACTIVITIES.each do |attrs|
    now = Time.now
    db[:activities].insert(
      **attrs,
      created_at: now,
      updated_at: now
    )
  end

  db
end
