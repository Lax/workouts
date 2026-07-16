Sequel.migration do
  change do
    add_column :activities, :divisions, :text
  end
end
