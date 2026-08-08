require "thor"
require "sequel"
require "sqlite3"
require "faraday"
require "yaml"
require "json"
require "nokogiri"
require "securerandom"

module Workouts
  class Error < StandardError; end
  class SyncError < Error; end
  class AuthError < Error; end
  class ConfigError < Error; end
  class ParseError < Error; end
end

require_relative "workouts/version"
require_relative "workouts/source/keep"
require_relative "workouts/config"
require_relative "workouts/config_template"
require_relative "workouts/db/connection"
require_relative "workouts/db/activity"
require_relative "workouts/db/rebuild"
require_relative "workouts/privacy/polyline_filter"
require_relative "workouts/geo"
require_relative "workouts/timezone/resolver"
require_relative "workouts/sport_mapper"
require_relative "workouts/parser"
require_relative "workouts/sync/base"
require_relative "workouts/sync/strava"
require_relative "workouts/sync/garmin_base"
require_relative "workouts/sync/garmin_base_di"
require_relative "workouts/sync/garmin"
require_relative "workouts/sync/garmin_cn"
require_relative "workouts/sync/keep"
require_relative "workouts/sync/igpsport"
require_relative "workouts/sync/xoss"
require_relative "workouts/sync/xingzhe"
require_relative "workouts/fit"
require_relative "workouts/auth"
require_relative "workouts/cli"
