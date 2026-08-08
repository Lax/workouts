require "git-fit"
require "thor"
require "sequel"
require "sqlite3"
require "faraday"
require "yaml"
require "json"
require "webrick"
require "securerandom"

module Workouts
  class Error < StandardError; end
  class SyncError < Error; end
  class AuthError < Error; end
  class ConfigError < Error; end
  class ParseError < Error; end
end

require_relative "workouts/version"
require_relative "workouts/config"
require_relative "workouts/db/connection"
require_relative "workouts/db/rebuild"
require_relative "workouts/sync/base"
require_relative "workouts/sync/garmin_base"
require_relative "workouts/sync/garmin_cn"
require_relative "workouts/sync/xoss"
require_relative "workouts/sync/xingzhe"
require_relative "workouts/auth"
require_relative "workouts/cli"
