Sequel.migration do
  up do
    create_table?(:activities) do
      Integer :id, primary_key: true
      String :run_id, null: false, unique: true
      String :name
      Float :distance
      Integer :moving_time
      Integer :elapsed_time
      String :sport_category, null: false, default: "run"
      String :sport_type
      String :start_date
      String :start_date_local
      String :location_country
      String :summary_polyline, text: true
      Float :average_heartrate
      Float :max_heartrate
      Float :average_cadence
      Float :max_cadence
      Float :average_power
      Float :max_power
      Float :average_temperature
      Integer :calories
      Float :average_speed
      Float :elevation_gain
      String :source
      String :duplicate_info, text: true
      String :divisions, text: true
      String :title, text: true
      String :external_id
      DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP

      index :start_date
      index :source
      index :sport_category
      index :external_id
    end

    create_table?(:dedup_groups) do
      primary_key :id
      String :group_id, null: false, unique: true
      DateTime :created_at
      DateTime :updated_at
    end

    create_table?(:dedup_group_members) do
      primary_key :id
      foreign_key :group_id, :dedup_groups, type: String, key: :group_id, null: false
      String :run_id, null: false
      String :source
      String :flag
      Float :confidence
      unique [:group_id, :run_id]
      index :run_id
    end
  end

  down do
    drop_table?(:dedup_group_members)
    drop_table?(:dedup_groups)
    drop_table?(:activities)
  end
end
