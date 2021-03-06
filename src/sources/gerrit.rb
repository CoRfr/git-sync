require 'colored'
require 'net/ssh'
require 'json'

class GitSync::Source::Gerrit
  attr_accessor :filters, :dry_run
  attr_reader :host, :port, :username, :to, :one_shot, :projects, :queue

  def initialize(host, port, username, from, to, one_shot=false)
    @dry_run = false
    @host = host
    @port = port
    @username = username

    @from = from
    if not @from
      @from = "ssh://"
      @from += "#{username}@" if username
      @from += "#{host}:#{port}/"
    end

    @to = to
    @filters = []
    @one_shot = one_shot

    @projects = {}

    @mutex = Mutex.new
    @done = ConditionVariable.new
  end

  def project_filtered_out?(project)
    return false if @filters.empty?

    @filters.each do |filter|
      if filter.class == Regexp
        return false if filter.match(project)
      else
        return false if project == filter
      end
    end

    true
  end

  def ls_projects
    all_projects = []

    puts "[Gerrit #{host}:#{port}] List projects through SSH (username: #{username})".green

    Net::SSH.start(@host,
                   @username,
                   port: @port) do |ssh|

      list = ssh.exec!("gerrit ls-projects --type ALL")
      list.each_line do |line|
        project = line.strip
        all_projects.push project
      end
    end

    all_projects
  end

  def process_event(line)
    puts "[Gerrit #{host}:#{port}] Processing event".blue
    event = JSON.parse(line)
    yield(event)
  end

  def stream_events
    puts "[Gerrit #{host}:#{port}] Streaming events through SSH (username: #{username})".blue

    Net::SSH.start(@host,
                   @username,
                   port: @port) do |ssh|

      ssh.open_channel do |channel|
        channel.exec("gerrit stream-events") do |ch, success|
          abort "could not execute command" unless success

          channel.on_data do |ch2, data|
            puts "[Gerrit #{host}:#{port}] #{data}"
            data.each_line do |line|
              process_event(line) do |event|
                yield(event)
              end
            end
          end

          channel.on_extended_data do |ch2, type, data|
            puts "[Gerrit #{host}:#{port}] Error #{data}".red
          end

          channel.on_eof do |ch2|
            puts "[Gerrit #{host}:#{port}] EOF".red
          end

          channel.on_close do |ch2|
            puts "[Gerrit #{host}:#{port}] Channel is closing!".red
          end
        end
      end

      ssh.loop
    end
  end

  def work(queue)
    @queue = queue

    # Init: replicate all projects
    ls_projects.each do |project_name|
      queue_project(project_name)
    end

    @done.signal

    return if one_shot

    handle_events
  end

  def wait
    if not one_shot
      loop do
        begin
          sleep
        rescue Interrupt
        end
      end
    end

    @mutex.synchronize { @done.wait(@mutex) }

    # Wait for all projects to be synchronized
    @projects.values.each do |p|
      p.wait
    end
  end

  def handle_events
    loop do
      begin
        stream_events do |event|
          event_type = event["type"]

          case event_type
          when "ref-updated",
               "patchset-created",
               "change-merged",
               "draft-published",
               "project-created" then
            puts "[Gerrit #{host}:#{port}] Handling event #{event_type}".green
            project_name = event["change"]["project"] if event["change"]
            project_name = event["refUpdate"]["project"] if event["refUpdate"]
            project_name = event["projectName"] if event["projectName"]

            raise "Unable to get project name for event #{event_type}: #{event}" if not project_name

            queue_project(project_name)
          else
            puts "[Gerrit #{host}:#{port}] Skipping event #{event["type"]}".yellow
          end
        end
      rescue Exception => e
        puts "[Gerrit #{host}:#{port}] Exception #{e.message}".red
      end

      delay = 30
      puts "[Gerrit #{host}:#{port}] Stream events returned, re-launching in #{delay}s ...".red
      sleep delay
    end
  end

  def task_project(project_name)
    # Return existing object if already initialized
    return projects[project_name] if projects[project_name]

    if project_filtered_out? project_name
      puts "Project #{project_name} is filtered out".yellow
      return nil
    else
      puts "Scheduling sync for project #{project_name}".green
    end

    p_from = File.join(@from, "#{project_name}")
    p_to = File.join(@to, "#{project_name}.git")

    projects[project_name] = GitSync::Source::Single.new(p_from, p_to, dry_run: dry_run)
  end

  def queue_project(project_name)
    project = task_project(project_name)
    queue << project if project
  end
end

