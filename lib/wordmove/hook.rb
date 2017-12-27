module Wordmove
  class Hook
    def self.logger
      Logger.new(STDOUT).tap { |l| l.level = Logger::DEBUG }
    end

    def self.run(action, step, cli_options)
      movefile = Wordmove::Movefile.new(cli_options[:config])
      options = movefile.fetch(false)
      environment = movefile.environment(cli_options)

      hooks = Wordmove::Hook::Config.new(
        options[environment][:hooks],
        action,
        step
      )

      unless hooks.local_hooks.empty?
        Wordmove::Hook::Local.run(hooks.local_hooks, cli_options[:simulate])
      end

      return if hooks.remote_hooks.empty?

      if options[environment][:ftp]
        logger.debug "You have configured remote hooks to run over "\
                     "an FTP connections, but this is not possible. Skipping."

        return
      end

      Wordmove::Hook::Remote.run(
        hooks.remote_hooks, options[environment][:ssh], cli_options[:simulate]
      )
    end

    Config = Struct.new(:options, :action, :step) do
      def empty?
        (local_hooks + remote_hooks).empty?
      end

      def local_hooks
        return [] if empty_step?

        options[action][step][:local] || []
      end

      def remote_hooks
        return [] if empty_step?

        options[action][step][:remote] || []
      end

      private

      def empty_step?
        return true unless options
        return true if options[action].nil?
        return true if options[action][step].nil?

        false
      end
    end

    class Local
      def self.logger
        parent.logger
      end

      def self.run(commands, simulate = false)
        logger.task "Running local hooks"

        commands.each do |command|
          logger.task_step true, "Exec command: #{command}"
          return true if simulate

          stdout_return = `#{command}`
          logger.task_step true, "Local output: #{stdout_return}"
        end
      end
    end

    class Remote
      def self.logger
        parent.logger
      end

      def self.run(commands, ssh_options, simulate = false)
        logger.task "Running remote hooks"

        copier = Photocopier::SSH.new(ssh_options).tap { |c| c.logger = logger }
        commands.each do |command|
          logger.task_step false, "Exec command: #{command}"
          return true if simulate

          stdout, stderr, exit_code = copier.exec! command

          logger.task_step false, "Remote output: #{stdout}"
          if exit_code.zero?
            logger.success ""
            next
          end

          logger.error "Error code #{exit_code} returned by remote command `#{command}`: #{stderr}"
        end
      end
    end
  end
end
