Gem::Specification.new do |s|
  s.name = "workouts-cli"
  s.version = "0.1.0"
  s.summary = "Workouts — Yet Another Training Aggregator"
  s.description = "Thin shell for the git-fit gem — interactive auth plus delegated commands (db/geo/parse/init)."
  s.authors = ["Lax"]
  s.homepage = "https://github.com/lax/workouts"
  s.license = "MIT"

  s.files = Dir["lib/**/*", "db/**/*", "config/**/*"]
  s.bindir = "exe"
  s.executables = ["workouts"]

  s.required_ruby_version = ">= 3.4"

  s.add_dependency "thor", "~> 1.3"
  s.add_dependency "sequel", "~> 5.0"
  s.add_dependency "sqlite3", "~> 2.0"
  s.add_dependency "faraday", "~> 2.0"
  s.add_dependency "base64", "~> 0.2"
  s.add_dependency "openssl", "~> 3.0"
  s.add_dependency "oauth", "~> 1.0"
  s.add_dependency "mini_racer", "~> 0.16"
  s.add_dependency "webrick", "~> 1.8"
  s.add_dependency "ostruct", "~> 0.6"
  s.add_dependency "rubyzip", "~> 2.3"
  s.add_dependency "tzinfo", "~> 2.0"
end
