#!/usr/bin/env ruby
# frozen_string_literal: true

# WAL checkpoint for manual DB-mutating workflows (danger-db-run callers).
# Usage: bundle exec ruby scripts/wal_checkpoint.rb <db-path>
# Truncates the WAL into the DB file and prints its byte size.

require "sequel"

db_path = ARGV[0]
abort "usage: wal_checkpoint.rb <db-path>" unless db_path && File.exist?(db_path)

db = Sequel.sqlite(db_path)
db.run("PRAGMA wal_checkpoint(TRUNCATE)")
print File.size(db_path)
