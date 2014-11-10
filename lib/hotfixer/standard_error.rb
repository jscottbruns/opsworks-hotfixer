class StandardError
  def initialize(msg = nil)
    @msg = msg
  end

  def message
    logger.error "(#{self.class}) #{@msg.to_s}".red
  end

  def logger
    @logger ||= Hotfixer.logger
  end
end

module Hotfixer
  class AWSError < StandardError; end
  class PatchError < StandardError; end
  class SSHAuthError < StandardError; end
  class InvalidIPError < StandardError; end
  class SSHCommandError < StandardError; end
  class Exception < StandardError; end
  class NoTagError < StandardError; end
end