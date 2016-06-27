require 'net/ssh'

class GitSync::Source::Gerrit
  attr_accessor :filters
  attr_reader :host, :port, :username, :to

  def initialize(host, port, username, from, to)
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

    puts "List projects through SSH @ #{host}:#{port} (username: #{username})".green

    Net::SSH.start(@host,
                   @username,
                   port: @port) do |ssh|

      list = ssh.exec!("gerrit ls-projects")
      list.each_line do |line|
        project = line.strip
        projects.push project
      end
    end

    projects
  end

  def sync!(dry_run=false)
    schedule.each do |task|
      task.sync(dry_run)
    end
  end

  def schedule
    tasks = []

    ls_projects.each do |project|
      if project_filtered_out? project
        puts "Project #{project} is filtered out".yellow
        next
      else
        puts "Scheduling sync for project #{project}".green
      end

      p_from = File.join(@from, "#{project}")
      p_to = File.join(@to, "#{project}.git")

      tasks.push GitSync::Source::Single.new(p_from, p_to)
    end

    return tasks
  end
end