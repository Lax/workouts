Sequel.migration do
  up do
    create_table(:dedup_groups) do
      primary_key :id
      String :group_id, null: false, unique: true
      DateTime :created_at
      DateTime :updated_at
    end

    create_table(:dedup_group_members) do
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
    drop_table(:dedup_group_members)
    drop_table(:dedup_groups)
  end
end
