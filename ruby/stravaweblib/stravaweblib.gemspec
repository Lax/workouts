require_relative "lib/stravaweblib/version"

Gem::Specification.new do |s|
  s.name        = "stravaweblib"
  s.version     = StravaWebLib::VERSION
  s.summary     = "Strava website client — login, session persistence, original file download"
  s.description = "Web-scraping client for the Strava website. Handles JWT/password authentication with persistent session caching, and downloads original activity files (FIT/GPX/TCX) and Strava-processed exports (TCX/GPX) from web endpoints that bypass API rate limits."
  s.authors     = ["Lax"]
  s.homepage    = "https://github.com/lax/workouts"
  s.license     = "MIT"

  s.files       = Dir["lib/**/*.rb"]
  s.required_ruby_version = ">= 3.4"

  s.add_dependency "faraday", "~> 2.0"
  s.add_dependency "faraday-cookie_jar", "~> 0.0"
end
