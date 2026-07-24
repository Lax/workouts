require "fileutils"
require "sequel"

module Workouts
  module DB
    class RebuildError < StandardError; end

    module Rebuild
      def self.call(db, db_path, migrations_path)
        backup = "#{db_path}.rebuild_bak"
        FileUtils.cp(db_path, backup)

        tables = db.tables - [:schema_migrations]
        data = {}
        tables.each { |t| data[t] = export_table(db, t) }

        db.run("PRAGMA foreign_keys = OFF")
        tables.each { |t| db.drop_table(t) }

        Sequel.extension :migration
        Sequel::Migrator.run(db, migrations_path)

        new_tables = db.tables.to_set
        data.each do |table, rows|
          next if table == :schema_info
          next unless new_tables.include?(table)
          import_table(db, table, rows) if rows.any?
        end

        warn "Rebuilt #{db_path}: #{data.values.sum(&:size)} rows from #{data.size} tables"
      rescue => e
        if backup && File.exist?(backup)
          FileUtils.cp(backup, db_path)
        end
        raise RebuildError, "Rebuild failed: #{e.message}"
      end

      def self.export_table(db, table)
        db[table].all.map { |r| r.except(:id) }
      end

      def self.import_table(db, table, rows)
        return if rows.empty?
        target = db[table].columns - [:id]
        filtered = rows.map { |r| r.select { |k, _| target.include?(k) } }
        db[table].multi_insert(filtered)
      end
    end
  end
end
