Sequel.migration do
  change do
    add_column :activities, :title, String, text: true
  end
end
