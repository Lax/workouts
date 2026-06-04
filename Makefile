SHELL := /bin/bash
BUNDLE := bundle exec

.PHONY: all sync export install build test console help

install:
	bundle install

sync:
	$(BUNDLE) exe/workouts sync

export:
	$(BUNDLE) exe/workouts export all

all: sync export

migrate:
	$(BUNDLE) exe/workouts db migrate

build:
	gem build workouts-cli.gemspec

test:
	bundle exec rspec

console:
	bundle exec pry

help:
	@echo "Commands:"
	@echo "  make install   - Install dependencies"
	@echo "  make sync      - Sync all workout data"
	@echo "  make export    - Export all formats"
	@echo "  make all       - Sync + export"
	@echo "  make build     - Build the gem"
	@echo "  make test      - Run tests"
	@echo "  make console   - Open Pry console"
