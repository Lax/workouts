require "thor"

module Workouts
  class DbCLI < Thor
    desc "migrate", "Run database migrations"
    def migrate
      config = Workouts::Config.new
      Workouts::DB::Connection.new(config.db_path)
      say_status :done, "Migrations up to date", :green
    rescue => e
      say_status :error, "Migration failed: #{e.message}", :red
    end
  end
end
