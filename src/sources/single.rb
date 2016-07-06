require 'colored'
require 'git'

class GitSync::Source::Single
  attr_accessor :dry_run
  attr_reader :from, :to

  def initialize(from, to, opts={})
    @dry_run = opts[:dry_run] || false
    @from = from
    @to = to
  end

  def work(pool)
    sync!
  end

  def sync!
    puts "Sync '#{from}' to '#{to} (dry run: #{dry_run})".blue

    if not File.exist?(to)
      puts "[#{to}] Cloning ..."
      if not dry_run
        pid = Process.fork {
          Git.clone(from, File.basename(to), path: File.dirname(to), mirror: true)
        }
        Process.waitpid(pid)
      end
    else
      puts "[#{to}] Updating ..."
      if not dry_run
        pid = Process.fork {
          git = Git.bare(to)
          if not git.remotes.map{|b| b.name}.include?('gitsync')
            git.add_remote("gitsync", from, :mirror => 'fetch')
          end
          git.fetch("gitsync")
        }
        Process.waitpid(pid)
      end
    end

    puts "[#{to}] Done ..."
  end

  def tasks
    return [ self ]
  end
end
