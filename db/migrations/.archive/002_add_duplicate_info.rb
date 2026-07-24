Sequel.migration do
  up do
    add_column :activities, :duplicate_info, String, text: true
  end

  down do
    drop_column :activities, :duplicate_info
  end
end
