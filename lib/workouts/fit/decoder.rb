require "mini_racer"
require "json"

module Workouts
  module FIT
    class Decoder
      JS_CODE = File.read(File.join(__dir__, "decoder.js")).freeze
      CTX = MiniRacer::Context.new.tap { |c| c.eval(JS_CODE) }

      def self.decode(path)
        bytes = File.read(path, mode: "rb").bytes
        json = CTX.eval("FitDecoder.decodeFit(#{bytes.inspect})")
        JSON.parse(json)
      end

      def self.info(path)
        bytes = File.read(path, mode: "rb").bytes
        json = CTX.eval("FitDecoder.fitInfo(#{bytes.inspect})")
        JSON.parse(json)
      end
    end
  end
end
