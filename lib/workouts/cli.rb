module Workouts
  require_relative "cli/sync"

  class CLI < Thor
    package_name "Workouts"

    class_option :config, type: :string, desc: "Path to config file", aliases: "-c"
    class_option :db, type: :string, desc: "Database path override"

    def self.exit_on_failure?
      true
    end

    include Cli::Sync

    desc "auth SOURCE", "Authenticate with a sync source (strava, garmin, garmin_cn, xoss, xingzhe)"
    def auth(source)
      if source == "strava"
        Auth::Strava.new(options, workouts_config).call
      else
        super
      end
    rescue Workouts::AuthError => e
      say_status :error, "Auth failed: #{e.message}", :red
    rescue => e
      say_status :error, e.message, :red
    end

    desc "db SUBCOMMAND", "Database operations (delegated to git fit)"
    def db(*args)
      gitfit_args = ["db", *args]
      gitfit_args.insert(1, "-c", options[:config]) if options[:config]
      GitFit::CLI.start(gitfit_args)
    end

    desc "geo SUBCOMMAND", "Detect geographical regions (delegated to git fit)"
    def geo(*args)
      gitfit_args = ["geo", *args]
      gitfit_args.insert(1, "-c", options[:config]) if options[:config]
      GitFit::CLI.start(gitfit_args)
    end

    desc "init", "Generate default config.yml (delegated to git fit)"
    option :output, type: :string, desc: "Output path", aliases: "-o"
    def init
      gitfit_args = ["init"]
      gitfit_args += ["-c", options[:config]] if options[:config]
      gitfit_args += ["-o", options[:output]] if options[:output]
      GitFit::CLI.start(gitfit_args)
    end

    desc "parse FILE", "Parse a GPX or TCX file (delegated to git fit)"
    option :save, type: :boolean, desc: "Save parsed activities to database", aliases: "-s"
    def parse(file)
      gitfit_args = ["parse", file]
      gitfit_args.insert(1, "-c", options[:config]) if options[:config]
      gitfit_args << "-s" if options[:save]
      GitFit::CLI.start(gitfit_args)
    end

    desc "version", "Show version"
    def version
      puts "Workouts v#{Workouts::VERSION}"
    end

    no_commands do
      def workouts_config
        @workouts_config ||= begin
          cfg = respond_to?(:options) ? options[:config] : nil
          cfg = cfg.to_s if cfg
          Workouts::Config.new(cfg)
        end
      end

      def db_path
        (respond_to?(:options) ? options[:db] : nil) || workouts_config.db_path
      end
    end

    private

    def connect_db
      Workouts::DB::Connection.new(db_path).db
    end
  end
end
