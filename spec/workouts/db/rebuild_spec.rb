RSpec.describe Workouts::DB::Rebuild do
  let(:db) { Sequel.sqlite("") }
  let(:tmpdir) { Dir.mktmpdir("rebuild-test-") }

  after { FileUtils.rm_rf(tmpdir) }

  describe ".export_table" do
    before do
      db.create_table(:items) do
        Integer :id, primary_key: true
        String :name
        Integer :value
      end
      db[:items].insert(name: "foo", value: 1)
      db[:items].insert(name: "bar", value: 2)
    end

    it "exports rows without :id" do
      rows = described_class.export_table(db, :items)
      expect(rows.size).to eq(2)
      expect(rows.first.keys).not_to include(:id)
      expect(rows.first.keys).to include(:name, :value)
    end

    it "returns empty array for empty table" do
      db.create_table(:empty) { Integer :id, primary_key: true }
      expect(described_class.export_table(db, :empty)).to eq([])
    end
  end

  describe ".import_table" do
    before do
      db.create_table(:items) do
        Integer :id, primary_key: true
        String :name
        Integer :value
      end
    end

    it "inserts rows matching new schema columns" do
      rows = [{name: "a", value: 1}, {name: "b", value: 2}]
      described_class.import_table(db, :items, rows)
      expect(db[:items].count).to eq(2)
      expect(db[:items].first[:name]).to eq("a")
    end

    it "filters out columns not in new schema" do
      rows = [{name: "a", value: 1, extra: "x"}]
      described_class.import_table(db, :items, rows)
      expect(db[:items].count).to eq(1)
      expect(db[:items].first.keys).not_to include(:extra)
    end

    it "does nothing for empty rows" do
      described_class.import_table(db, :items, [])
      expect(db[:items].count).to eq(0)
    end
  end

  describe ".call" do
    let(:db_path) { File.join(tmpdir, "test.db") }
    let(:migrations_path) { File.join(tmpdir, "migrations") }

    before do
      FileUtils.mkdir_p(migrations_path)
      File.write(File.join(migrations_path, "001_test.rb"), <<~MIG)
        Sequel.migration do
          up do
            create_table?(:items) do
              Integer :id, primary_key: true
              String :name
              Integer :value
            end
          end
          down { drop_table?(:items) }
        end
      MIG
    end

    context "fresh DB" do
      it "runs migration normally" do
        source = Sequel.sqlite(db_path)
        Sequel.extension :migration
        Sequel::Migrator.run(source, migrations_path)
        source[:items].insert(name: "keep", value: 42)
        source.disconnect

        target = Sequel.sqlite(db_path)
        described_class.call(target, db_path, migrations_path)
        expect(target[:items].count).to eq(1)
        expect(target[:items].first[:name]).to eq("keep")
        expect(File).not_to exist("#{db_path}.rebuild_bak")
      end
    end

    context "with extra columns in old table" do
      it "drops unknown columns on import" do
        source = Sequel.sqlite(db_path)
        source.create_table(:items) do
          Integer :id, primary_key: true
          String :name
          Integer :value
          String :legacy
        end
        source[:items].insert(name: "old", value: 1, legacy: "gone")
        source.disconnect

        target = Sequel.sqlite(db_path)
        described_class.call(target, db_path, migrations_path)
        rows = target[:items].all
        expect(rows.size).to eq(1)
        expect(rows.first[:name]).to eq("old")
        expect(rows.first).not_to have_key(:legacy)
      end
    end

    context "backup recovery on error" do
      it "restores backup when rebuild fails" do
        source = Sequel.sqlite(db_path)
        source.create_table(:items) {
          Integer :id, primary_key: true
          String :name
        }
        source[:items].insert(name: "safe")
        source.disconnect

        target = Sequel.sqlite(db_path)
        broken_path = File.join(tmpdir, "nonexistent")
        expect do
          described_class.call(target, db_path, broken_path)
        end.to raise_error(Workouts::DB::RebuildError)

        recovered = Sequel.sqlite(db_path)
        expect(recovered.table_exists?(:items)).to be true
        expect(recovered[:items].first[:name]).to eq("safe")
      end
    end

    context "WAL mode backup" do
      it "backs up and restores -wal and -shm files" do
        source = Sequel.sqlite(db_path)
        source.run("PRAGMA journal_mode=WAL")
        source.create_table(:items) {
          Integer :id, primary_key: true
          String :name
        }
        source[:items].insert(name: "wal_test")
        source.disconnect

        target = Sequel.sqlite(db_path)
        described_class.call(target, db_path, migrations_path)
        expect(target[:items].count).to eq(1)
        expect(File).not_to exist("#{db_path}.rebuild_bak")
      end
    end

    context "with schema_info version from old migrations" do
      it "does not re-import schema_info (version managed by migrator)" do
        source = Sequel.sqlite(db_path)
        Sequel.extension :migration
        Sequel::Migrator.run(source, migrations_path)
        source[:schema_info].insert(version: 999)
        source[:items].insert(name: "keep", value: 42)
        source.disconnect

        target = Sequel.sqlite(db_path)
        described_class.call(target, db_path, migrations_path)

        version = target[:schema_info].first[:version]
        expect(version).not_to eq(999)
        expect(target[:items].count).to eq(1)
        expect(target[:items].first[:name]).to eq("keep")
      end
    end
  end
end
