module StravaWebLib
  class Error < StandardError; end
  class AuthError < Error; end
  class ExportError < Error; end
  class NotFoundError < ExportError; end
end
