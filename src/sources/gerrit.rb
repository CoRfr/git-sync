require 'net/ssh'
require 'json'

class GitSync::Source::Gerrit
  attr_accessor :filters, :dry_run
  attr_reader :host, :port, :username, :to, :one_shot

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
    projects = []

    puts "[Gerrit #{host}:#{port}] List projects through SSH (username: #{username})".green

    Net::SSH.start(@host,
                   @username,
                   port: @port) do |ssh|

      list = ssh.exec!("gerrit ls-projects --type ALL")
      list.each_line do |line|
        project = line.strip
        projects.push project
      end
    end

    projects
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

          channel.on_close do |ch2|
            puts "[Gerrit #{host}:#{port}] Channel is closing!".red
          end
        end
      end

      ssh.loop
    end
  end

  def sync!
    schedule.each do |task|
      task.sync
    end
  end

  def work(group)
    return if one_shot

    stream_events do |event|
      case event["type"]
      when "ref-updated",
           "patchset-updated",
           "change-merged" then
        project = event["change"]["project"] if event["change"]
        project = event["refUpdate"]["project"] if event["refUpdate"]
        task = task_project(project)
        group.add(:max_tries => 2) do
          task.work(group)
        end if task
      else
        puts "[Gerrit #{host}:#{port}] Skipping event #{event["type"]}".yellow
      end
    end
  end

  def task_project(project)
    if project_filtered_out? project
      puts "Project #{project} is filtered out".yellow
      return nil
    else
      puts "Scheduling sync for project #{project}".green
    end

    p_from = File.join(@from, "#{project}")
    p_to = File.join(@to, "#{project}.git")

    GitSync::Source::Single.new(p_from, p_to, dry_run: dry_run)
  end

  def tasks
    t = [self]

    ls_projects.each do |project|
      task = task_project(project)
      t.push(task) if task
    end

    t
  end
end

