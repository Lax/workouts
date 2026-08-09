require "git-fit"
require "thor"

module Workouts
  class Error < StandardError; end
  class SyncError < Error; end
  class AuthError < Error; end
  class ConfigError < Error; end
  class ParseError < Error; end
end

require_relative "workouts/version"
require_relative "workouts/cli"
