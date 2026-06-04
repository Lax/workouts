require "thor"
require "sequel"
require "sqlite3"
require "faraday"
require "faraday/multipart"
require "yaml"
require "json"
require "csv"
require "nokogiri"

module Workouts
  class Error < StandardError; end
end

require_relative "workouts/version"
require_relative "workouts/config"
require_relative "workouts/config_template"
require_relative "workouts/db/connection"
require_relative "workouts/db/activity"
require_relative "workouts/privacy/polyline_filter"
require_relative "workouts/sync/base"
require_relative "workouts/sync/strava"
require_relative "workouts/sync/garmin"
require_relative "workouts/sync/garmin_cn"
require_relative "workouts/sync/keep"
