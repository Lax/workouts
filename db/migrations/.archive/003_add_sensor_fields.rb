Sequel.migration do
  change do
    add_column :activities, :average_cadence,     Float
    add_column :activities, :max_cadence,          Float
    add_column :activities, :average_power,        Float
    add_column :activities, :max_power,            Float
    add_column :activities, :max_heartrate,        Float
    add_column :activities, :calories,             Integer
    add_column :activities, :average_temperature,  Float
  end
end
