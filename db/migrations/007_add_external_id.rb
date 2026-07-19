Sequel.migration do
  change do
    add_column :activities, :external_id, String
    add_index :activities, :external_id
  end
end
