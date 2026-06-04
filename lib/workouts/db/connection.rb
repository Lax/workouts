require "fileutils"

module Workouts
  module DB
    class Connection
      def initialize(db_path)
        FileUtils.mkdir_p(File.dirname(db_path)) if db_path.include?("/")
        @db = Sequel.sqlite(db_path)
        run_migrations
      end

      def db
        @db
      end

      private

      def run_migrations
        Sequel.extension :migration
        Sequel::Migrator.run(@db, File.expand_path("../../../db/migrations", __dir__))
      end
    end
  end
end
