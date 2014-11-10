require 'hotfixer/version'
require 'logger'

module Hotfixer
  NAME = "OpsWorks Hotfixer"
  LICENSE = "GNU"

  DEFAULTS = {
    :verbose => false,
    :layer       => 'rails-app',
    :instance    => [],
    :docroot     => '/srv/www/<project>/current',
    :awskey      => ENV['AWS_ACCESS_KEY'],
    :awssecret   => ENV['AWS_SECRET_KEY'],
    :region      => 'us-east-1',
    :restart_cmd => 'touch tmp/restart.txt',
    :sudo        => true,
    :deploy_user => 'deploy',
    :reset       => false
  }

  REQUIRED = [:stackid, :user, :identityfile, :awskey, :awssecret, :appname]

  def self.options
    @options ||= DEFAULTS.dup
  end

  def self.logger
    @logger ||= Logger.new(STDOUT)
  end
end
