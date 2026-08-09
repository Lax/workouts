SHELL := /bin/bash
BUNDLE := bundle exec

.PHONY: all sync export install build test console help

install:
	bundle install

sync:
	$(BUNDLE) git fit sync

export:
	$(BUNDLE) git fit export json

all: sync export

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
	@echo "  make export    - Export JSON"
	@echo "  make all       - Sync + export"
	@echo "  make build     - Build the gem"
	@echo "  make test      - Run tests"
	@echo "  make console   - Open Pry console"
