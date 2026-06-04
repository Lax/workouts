FROM ruby:3.4-slim

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential libsqlite3-dev git ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock workouts-cli.gemspec ./
COPY lib/workouts/version.rb lib/workouts/version.rb

RUN bundle install --jobs=4 --retry=3

COPY . .

RUN bundle install --jobs=4 --retry=3

ENTRYPOINT ["bundle", "exec", "exe/workouts"]
