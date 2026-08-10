Gem::Specification.new do |s|
  s.name = "workouts-cli"
  s.version = "0.1.0"
  s.summary = "Workouts — Yet Another Training Aggregator"
  s.description = "Thin shell for the git-fit gem — auth delegation plus delegated commands (db/geo/parse/init)."
  s.authors = ["Lax"]
  s.homepage = "https://github.com/lax/workouts"
  s.license = "MIT"

  s.files = Dir["lib/**/*"]
  s.bindir = "exe"
  s.executables = ["workouts"]

  s.required_ruby_version = ">= 3.4"

  s.add_dependency "git-fit", "~> 0.12.0"
  s.add_dependency "thor", "~> 1.3"
end
