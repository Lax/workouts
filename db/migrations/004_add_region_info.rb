Sequel.migration do
  change do
    add_column :activities, :region_info, :text
  end
end
