$stdout.sync = true

require 'optparse'
require 'singleton'
require 'aws-sdk'
require 'colored'

require 'hotfixer'
require 'hotfixer/ssh'
require 'hotfixer/standard_error'

module Hotfixer
  class CLI

    include Singleton

    def parse(args=ARGV)
      init_options(args)
      logger.level = options[:verbose] ? Logger::DEBUG : Logger::WARN
      validate!
    end

    def run
      begin
        load_instances(fetch_layer).reject! { |i| i[:status] != 'online' }.each do |i|
          next if options[:instance].count > 0 && ! options[:instance].include?(i[:hostname])
          logger.info "Connecting to remote host #{i[:hostname]}"

          SSH.new(:public_ip => i[:public_ip]) do |ssh|

            ssh.diff_tag do |tag, log|
              if ! options[:rollback] && log.count == 0
                logger.warn "No diffs in tag #{options[:tag]}, nothing to patch"
                next
              end

              logger.warn "Remote host is on tag #{tag}, " + ( options[:rollback] ? "rollbacking back to this version " : "patching host #{i[:hostname]} with tag #{options[:tag]} (#{log.count} commits)" )
              print "\n\nRemote host is on tag #{tag}, " + ( options[:rollback] ? "rollback to this version? " : "patch host #{i[:hostname]} with tag #{options[:tag]} (#{log.count} commits)?" ) + " [Yn] ".green unless options[:yes]

              if options[:yes] || gets.chomp.downcase == 'y' || gets.chomp == ''
                begin
                  if options[:rollback]
                    ssh.rollback tag
                    logger.warn "Rollback successful, restarting remote application".green
                  else
                    ssh.patch_host tag
                    logger.warn "Patch applied successfully, restarting remote application".green
                  end

                  ssh.restart_host
                  logger.warn "Remote application restarted successfully on #{i[:hostname]}".green

                rescue PatchError, SSHCommandError
                  logger.error "Patch failed, try resetting codebase (--reset) or rolling back (--rollback)".red
                end
              else
                logger.warn "Skipping #{i[:hostname]}"
              end
            end
          end
        end
      rescue => e
        raise e.class, e.message
      end
    end

    private

    def load_instances(layer)
      raise AWS::OpsWorks::Errors::ResourceNotFoundException, "Unable to find layer #{options[:layer]}" if layer.nil?
      logger.info "Loading #{options[:layer]} (#{layer[:layer_id]}) instances"
      opsworks.client.describe_instances(:layer_id => layer[:layer_id]).first.pop
    end

    def fetch_layer
      logger.info "Looking up attributes for layer #{options[:layer]} on stack #{options[:stackid]}"
      opsworks.client.describe_layers(:stack_id => options[:stackid]).first.pop.reject! { |layer| layer[:shortname] != options[:layer] }.first
    end

    def opsworks
      @opsworks ||= AWS::OpsWorks.new(
        :access_key_id      => options[:awskey],
        :secret_access_key  => options[:awssecret],
        :region             => options[:region],
        :logger             => logger,
        :log_level          => :debug
      )
    end

    def die(code)
      exit(code)
    end

    def init_options(args)
      opts = parse_opts(args)
      options.merge!(opts)
    end

    def options
      Hotfixer.options
    end

    def logger
      Hotfixer.logger
    end

    def validate!
      missing = Hotfixer::REQUIRED.select{ |param| options[param].nil? }
      if not missing.empty? || ( missing.empty? && ! options[:tag] && ! options[:rollback] )
        Hotfixer::REQUIRED << :tag if ! options[:tag] && ! options[:rollback]
        puts "Missing required arguments: #{missing.join(', ')}"
        puts @parser
        die 1
      end

      options[:docroot].gsub!('<project>', options[:appname])
    end

    def parse_opts(argv)
      option = {}

      @parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"

        opts.on("-s", "--stackid STACK", "Opsworks stack id") do |opt|
          option[:stackid] = opt
        end

        opts.on("-t", "--tag TAG", "Tag (i.e. 1.2.3) of hotfix release #{default(:tag)}") do |opt|
          option[:tag] = opt
        end

        opts.on("-l", "--layer [LAYER]", "Short name of layer containing instances to hotfix #{default(:layer)}") do |opt|
          option[:layer] = opt
        end

        opts.on("--instance host1,host2,host3", Array, "Optional list of instances to hotfix within the layer, specified as instance hostname") do |opt|
          option[:instance] = opt
        end

        opts.on("-u", "--user USER", "SSH username #{default(:user)}") do |opt|
          option[:user] = opt
        end

        opts.on("-i", "--identity KEYFILE", "SSH identity file #{default(:identityfile)}") do |opt|
          option[:identityfile] = opt
        end

        opts.on("-y", "--deploy_user [DEPLOY_USER]", "Remote username for deployment #{default(:deploy_user)}") do |opt|
          option[:deploy_user] = opt
        end

        opts.on("-m", "--sudo [SUDO]", "Use sudo priviledges for remote deployment commands #{default(:sudo)}") do |opt|
          option[:sudo] = opt
        end

        opts.on("-z", "--restart_cmd [RESTART_CMD]", "Command to restart remote application #{default(:restart_cmd)}") do |opt|
          option[:restart_cmd] = opt
        end

        opts.on("-k", "--awskey [KEY]", "AWS API key (ENV[AWS_ACCESS_KEY])") do |opt|
          option[:key] = opt
        end

        opts.on("-x", "--awssecret [SECRET]", "AWS API secret (ENV[AWS_SECRET_KEY])") do |opt|
          option[:secret] = opt
        end

        opts.on("-r", "--awsregion [REGION]", "AWS region to connect to #{default(:region)}") do |opt|
          option[:region] = opt
        end

        opts.on("-p", "--awsprofile [PROFILE]", "Connect to AWS API using profile from AWS config #{default(:profile)}") do |opt|
          option[:profile] = opt
        end

        opts.on("-a", "--appname [APPNAME]", "Short name of project app #{default(:appname)}") do |opt|
          option[:appname] = opt
        end

        opts.on("-d", "--docroot [DOCROOT]", "Remote project document root directory #{default(:docroot)}") do |opt|
          option[:docroot] = opt
        end

        opts.on("--reset", "Reset remote code base before applying patch #{default(:reset)}") do |opt|
          option[:reset] = opt
        end

        opts.on("--rollback", "Rollback a previously applied patch #{default(:rollback)}") do |opt|
          option[:rollback] = opt
        end

        opts.on("--yes", "Assume Yes to all queries and do not prompt") do |opt|
          option[:yes] = opt
        end

        opts.on("-v", "--verbose", "Run verbosely") do |opt|
          option[:verbose] = opt
        end

        opts.on("-h", "--help", "Display this help message") do |opt|
          puts opts
          exit
        end
      end

      @parser.parse!(argv)
      option
    end

    def default(opt)
      return "[#{options[opt]}]" unless options[opt].nil?
    end
  end
end
