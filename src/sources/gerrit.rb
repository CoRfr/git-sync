require 'colored'
require 'net/ssh'
require 'json'
require 'bunny'

class GitSync::Source::Gerrit < GitSync::Source::Base
  attr_accessor :filters
  attr_reader :host, :port, :username, :from, :to, :one_shot, :projects, :queue

  def initialize(host, port, username, from, to, one_shot=false)
    super()
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

  def to_s
    "<Source::Gerrit #{from}>"
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
    raise NotImplementedError, "Implement this method in a child class"
  end

  def work(queue)
    @queue = queue

    remote_projects = ls_projects

    # Remove deleted projects if any
    check_local_projects(remote_projects)

    # Init: replicate all projects
    remote_projects.each do |project_name|
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
        rescue Interrupt => e
          STDERR.puts "Interrupt:"
          STDERR.puts e
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
            STDERR.puts "[Gerrit #{host}:#{port}] Handling event #{event_type}".green
            project_name = event["change"]["project"] if event["change"]
            project_name = event["refUpdate"]["project"] if event["refUpdate"]
            project_name = event["projectName"] if event["projectName"]

            raise "Unable to get project name for event #{event_type}: #{event}" if not project_name

            queue_project(project_name)
          else
            STDERR.puts "[Gerrit #{host}:#{port}] Skipping event #{event["type"]}".yellow
          end
        end
      rescue Exception => e
        STDERR.puts "[Gerrit #{host}:#{port}] Exception #{e.message}".red
      end

      delay = 5
      STDERR.puts "[Gerrit #{host}:#{port}] Stream events returned, re-launching in #{delay}s ...".red
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

  def check_local_projects(remote_projects)
    local_projects = Dir.glob("#{@to}/**/*.git")

    # Skip symlink to keep .repo/manifest.git
    local_projects = local_projects.reject { |x| File.symlink?(x) }

    remote_projects.each do |project_name|
      p_to = File.join(@to, "#{project_name}.git")

      local_projects = local_projects.reject {|x| x == p_to}
    end

    local_projects.each do |to|
      if same_remote?(to)
        puts "Deleting \"#{to}\" project from local disk!"
        FileUtils.rm_rf(to)
      end
    end

  end

  def same_remote?(to)
    same_remote = false
    git = Git.bare(to)

    # Look for the remote
    git.remotes.each do |remote|
      next if remote.name != "gitsync"

      if remote.url.index(@from) == 0
        same_remote = true
        break
      end
    end

    return same_remote
  end

end

