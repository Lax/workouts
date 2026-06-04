require "yaml"

module Workouts
  class Config
    DEFAULTS = {
      "database" => { "path" => "data/workouts.db" },
      "sync" => {},
      "export" => {
        "json" => { "path" => "data/activities.json" },
        "svg" => { "dir" => "data/svg" },
        "csv" => { "path" => "data/workouts.csv" }
      },
      "privacy" => {
        "start_end_range" => 200
      },
      "system" => {
        "units" => "metric",
        "log_level" => "info",
        "timezone" => "UTC"
      }
    }.freeze

    ENV_SEPARATOR = "__"

    def initialize(path = nil)
      @data = deep_dup(DEFAULTS)
      load_file(path) if path && File.exist?(path)
      load_env
    end

    def [](key)
      @data[key]
    end

    def sync_config(source)
      @data.dig("sync", source) || {}
    end

    def privacy_config
      @data["privacy"] || {}
    end

    def export_config
      @data["export"] || {}
    end

    def db_path
      @data.dig("database", "path") || "data/workouts.db"
    end

    private

    def load_file(path)
      yaml = YAML.safe_load(File.read(path)) || {}
      deep_merge!(@data, yaml)
    end

    def load_env
      ENV.each do |key, value|
        parts = key.downcase.split(ENV_SEPARATOR)
        next unless parts.size > 1

        set_nested(@data, parts, value) if key == key.upcase
      end
    end

    def set_nested(hash, keys, value)
      last = keys.pop
      keys.each { |k| hash[k] ||= {}; hash = hash[k] }
      hash[last] = typed_value(value)
    end

    def typed_value(str)
      case str
      when /\A\d+\z/ then str.to_i
      when /\A\d+\.\d+\z/ then str.to_f
      when /\Atrue\z/i then true
      when /\Afalse\z/i then false
      when /\Anil\z/i then nil
      else str
      end
    end

    def deep_dup(obj)
      case obj
      when Hash then obj.each_with_object({}) { |(k, v), h| h[k] = deep_dup(v) }
      when Array then obj.map { |v| deep_dup(v) }
      else obj
      end
    end

    def deep_merge!(target, source)
      source.each do |key, val|
        if val.is_a?(Hash) && target[key].is_a?(Hash)
          deep_merge!(target[key], val)
        else
          target[key] = deep_dup(val)
        end
      end
      target
    end
  end
end
