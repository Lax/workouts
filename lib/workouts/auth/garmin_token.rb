module Workouts
  module Auth
    class GarminToken
      def self.for_intl(config)
        authenticate_with(Workouts::Sync::Garmin, config, "garmin.com")
      end

      def self.for_cn(config)
        authenticate_with(Workouts::Sync::GarminCN, config, "garmin.cn")
      end

      def self.authenticate_with(klass, config, default_domain)
        adapter = klass.new(config: config, db: nil, activity_filter: nil)
        return nil unless adapter.authenticate

        token_hash = adapter.instance_variable_get(:@access_token) || {}
        domain = adapter.instance_variable_get(:@domain) || default_domain

        {access_token: token_hash["access_token"], domain: domain}
      end
      private_class_method :authenticate_with
    end
  end
end
