require "fileutils"
require "sequel"

module Workouts
  module DB
    class Connection
      def initialize(db_path)
        FileUtils.mkdir_p(File.dirname(db_path)) if db_path.include?("/")
        @db = Sequel.sqlite(db_path)
        @db.run("PRAGMA journal_mode=WAL")
        @db.run("PRAGMA busy_timeout=5000")
        run_migrations
      end

      def db
        @db
      end

      private

      def run_migrations
        Sequel.extension :migration
        path = File.expand_path("../../../db/migrations", __dir__)
        Sequel::Migrator.run(@db, path)
      rescue Sequel::Migrator::Error
        Workouts::DB::Rebuild.call(@db, @db.opts[:database], path)
        Sequel::Migrator.run(@db, path)
      end
    end
  end
end
