require 'serfx'
require 'blender/exceptions'
require 'blender/log'
require 'blender/drivers/base'
require 'json'

module Blender
  module Driver
    class SerfMulti < Base

      def initialize(events, config)
        @events = events
        @config = config
      end

      def raw_exec(command)
        responses = []
        query, payload = command.split(/\s+/, 2)
        Log.debug("Invoking serf query '#{query}' with payload '#{payload}' against #{@current_hosts}")
        Log.debug("Serf RPC address #{@config[:host]}:#{@config[:port]}")
        Serfx.connect(host: @config[:host], port: @config[:port]) do |conn|
          conn.query(query, payload, 'FilterNodes'=> @current_hosts, 'Timeout'=> 15*1e9.to_i) do |event|
            responses <<  event
          end
        end
        exit_status = responses.size == @current_hosts.size ? 0 : -1
        ExecOutput.new(exit_status, JSON.generate(responses), nil)
      end

      def execute(job)
        tasks = job.tasks
        hosts = job.hosts
        Log.debug("Serf execution tasks [#{tasks.inspect}]")
        Log.debug("Serf query on hosts [#{hosts.inspect}]")
        @current_hosts = hosts
        Array(tasks).each do |task|
          if evaluate_guards?(task)
            Log.debug("Host:#{hosts.size}| Guards are valid")
          else
            Log.debug("Host:#{hosts.size}| Guards are invalid")
            run_task_command(task)
          end
        end
      end

      def run_task_command(task)
         e_status = raw_exec(task.command).exitstatus
         if e_status != 0
           if task.metadata[:ignore_failure]
             Log.warn('Ignore failure is set, skipping failure')
           else
            raise Exceptions::ExecutionFailed, "Failed to execute '#{task.command}'"
           end
         end
      end
    end
  end
end