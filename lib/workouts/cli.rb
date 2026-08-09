module Workouts
  class CLI < Thor
    package_name "Workouts"

    class_option :config, type: :string, desc: "Path to config file", aliases: "-c"

    def self.exit_on_failure?
      true
    end

    desc "auth SOURCE", "Authenticate with a sync source (garmin, garmin_cn, strava)"
    option :A, type: :boolean, desc: "Garmin Strategy A: curl-impersonate shellout (git fit auth garmin)"
    option :B, type: :boolean, desc: "Garmin Strategy B: Playwright"
    option :auto, type: :boolean, desc: "Garmin auto: B first, fallback to A (default)"
    option :sync, type: :boolean, desc: "Garmin: promote cached token to auth_seed"
    option :mfa_code, type: :string, desc: "Garmin MFA code (from email), re-run to continue"
    def auth(source)
      case source
      when "garmin"
        delegate_auth
      when "garmin_cn", "strava"
        gitfit_args = ["auth", source]
        gitfit_args.insert(2, "-c", options[:config]) if options[:config]
        GitFit::CLI.start(gitfit_args)
      when "xoss", "xingzhe"
        say_status :warn,
          "#{source} self-authenticates during `git fit sync`; no interactive auth", :yellow
      else
        say_status :error, "Supported: garmin, garmin_cn, strava", :red
      end
    rescue GitFit::Sync::AuthError => e
      say_status :error, "Auth failed: #{e.message}", :red
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

    private

    def delegate_auth
      gitfit_args = ["auth", "garmin"]
      %i[A B].each { |flag| gitfit_args << "-#{flag}" if options[flag] }
      %i[auto sync].each { |flag| gitfit_args << "--#{flag}" if options[flag] }
      if options[:mfa_code] && !options[:mfa_code].to_s.strip.empty?
        gitfit_args += ["--mfa-code", options[:mfa_code].to_s]
      end
      gitfit_args.insert(2, "-c", options[:config]) if options[:config]
      GitFit::CLI.start(gitfit_args)
    end
  end
end
