require "mini_racer"
require "json"

module Workouts
  module FIT
    # Decode Garmin FIT binary via mini_racer + @garmin/fitsdk JS bundle.
    # Coordinates arrive as semicircles (range -1..1) → multiply by 180 for degrees.
    class Decoder
      JS_CODE = File.read(File.join(__dir__, "decoder.js")).freeze
      CTX = MiniRacer::Context.new.tap { |c| c.eval(JS_CODE) }

      def self.decode(path)
        bytes = File.read(path, mode: "rb").bytes
        json = CTX.eval("FitDecoder.decodeFit(#{bytes.inspect})")
        records = JSON.parse(json)
        records.each do |r|
          r["positionLat"] *= 180 if r["positionLat"]
          r["positionLong"] *= 180 if r["positionLong"]
        end
        records
      end

      def self.info(path)
        bytes = File.read(path, mode: "rb").bytes
        json = CTX.eval("FitDecoder.fitInfo(#{bytes.inspect})")
        JSON.parse(json)
      end
    end
  end
end
