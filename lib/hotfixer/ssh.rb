require 'net/ssh'
#require 'version_sorter'

module Hotfixer
  class SSH

    def initialize(opts = {})
      logger.info "Initializing Net::SSH with options => #{opts.inspect}"

      @options = Hotfixer.options.merge(opts)

      raise SSHAuthError, "Public key not specified" if @options[:identityfile].nil?
      raise InvalidIPError, "Invalid IP address specified" if @options[:public_ip].nil? || ! /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.match(@options[:public_ip])

      yield self
      close!
    end

    def diff_tag(&block)
      logger.info "Looking up project's current tag"

      curr_tag = ssh_exec!(command("git fetch --all >/dev/null && git describe")).first.chomp
      all_tags = ssh_exec!(command("git tag")).first.split("\n")

      raise NoTagError, "Can't find #{@options[:tag]} in tag list" unless all_tags.include?(@options[:tag]) || @options[:rollback]

      yield curr_tag, ssh_exec!(command("git log --oneline #{curr_tag}..#{@options[:tag]}")).first.split("\n")
    end

    def rollback(curr_tag=nil)
      raise NoTagError, "Can't identify current project tag, can't rollback codebase without current tag" if curr_tag.nil?
      logger.info "Rolling back to #{curr_tag}"
      ssh_exec! command("git reset --hard #{curr_tag}")
    end

    def patch_host(curr_tag=nil)
      raise NoTagError, "Can't identify current project tag, can't generate patch file without current tag" if curr_tag.nil?
      logger.info "Patching remote host..."

      if @options[:reset]
        logger.info "Resetting remote codebase to #{curr_tag}" if @options[:reset]
        ssh_exec! command("git reset --hard #{curr_tag}")
      end

      ssh_exec! command("git diff #{curr_tag}..#{@options[:tag]} -- | git apply -v -")
    end

    def restart_host
      logger.info "Restarting application on remote host"
      ssh_exec! command(@options[:restart_cmd])
    end

    private

    def command(cmd)
      @command ||= construct_command
      cmd = @command.gsub(/<command>/, cmd)
      logger.info cmd
      cmd
    end

    def construct_command
      @command = []
      @command << "cd #{@options[:docroot]} &&"
      @command << "sudo" if @options[:sudo]
      if @options[:deploy_user]
        @command << "su #{@options[:deploy_user]} -c '<command>'"
      else
        @command << "<command>"
      end

      @command.join ' '
    end

    def close!
      logger.info "Closing connection to remote host"
      ssh.close
    end

    def ssh_exec!(command)
      stdout_data = ""
      stderr_data = ""
      exit_code = nil
      exit_signal = nil

      ssh.open_channel do |channel|
        channel.exec(command) do |ch, success|
          unless success
            raise SSHCommandError, "FAILED: couldn't execute command (ssh.channel.exec)"
          end
          channel.on_data do |ch,data|
            stdout_data+=data
          end

          channel.on_extended_data do |ch,type,data|
            stderr_data+=data
          end

          channel.on_request("exit-status") do |ch,data|
            exit_code = data.read_long
          end

          channel.on_request("exit-signal") do |ch, data|
            exit_signal = data.read_long
          end
        end
      end
      ssh.loop
      raise SSHCommandError, stderr_data unless exit_code == 0
      [stdout_data, stderr_data]
    end

    def ssh
      @ssh ||= Net::SSH.start(
        @options[:public_ip], @options[:user],
        :keys => [ @options[:identityfile] ],
        :compression => 'zlib'
      )
    end

    def logger
      Hotfixer.logger
    end
  end
end
