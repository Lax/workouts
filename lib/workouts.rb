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
