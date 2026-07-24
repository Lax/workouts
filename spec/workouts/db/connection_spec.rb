RSpec.describe Workouts::DB::Connection do
  let(:db_path) { File.join(Dir.mktmpdir("conn-test-"), "test.db") }

  after { File.delete(db_path) if File.exist?(db_path) }

  describe "#initialize" do
    context "fresh database" do
      it "runs migrations without error" do
        expect { described_class.new(db_path) }.not_to raise_error
        expect(File.exist?(db_path)).to be true
      end
    end

    context "when migration version mismatches" do
      it "rebuilds database preserving data" do
        db = Sequel.sqlite(db_path)
        db.run("PRAGMA journal_mode=WAL")
        db.create_table?(:schema_info) { Integer :version }
        db[:schema_info].insert(version: 999)
        db.create_table?(:activities) do
          Integer :id, primary_key: true
          String :run_id, null: false, unique: true
          String :sport_category, null: false, default: "run"
          String :source
          DateTime :created_at, default: Sequel::CURRENT_TIMESTAMP
          DateTime :updated_at, default: Sequel::CURRENT_TIMESTAMP
        end
        db.create_table?(:dedup_groups) do
          primary_key :id
          String :group_id, null: false, unique: true
          DateTime :created_at
          DateTime :updated_at
        end
        db[:activities].insert(run_id: "test_1", sport_category: "run", source: "test")
        db[:dedup_groups].insert(group_id: "group_abc", created_at: Time.now, updated_at: Time.now)
        db.disconnect

        conn = described_class.new(db_path)
        expect(conn.db.table_exists?(:activities)).to be true
        expect(conn.db.table_exists?(:dedup_groups)).to be true
        expect(conn.db[:activities].count).to eq(1)
        expect(conn.db[:activities].first[:run_id]).to eq("test_1")
        expect(conn.db[:dedup_groups].count).to eq(1)
        expect(conn.db[:dedup_groups].first[:group_id]).to eq("group_abc")
        expect(File.exist?("#{db_path}.rebuild_bak")).to be true
      end
    end
  end
end
