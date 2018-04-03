require 'colored'
require 'git'
require 'date'
require 'fileutils'

class GitSync::Source::Single
  attr_accessor :dry_run
  attr_reader :from, :to

  def initialize(from, to, opts={})
    @dry_run = opts[:dry_run] || false
    @from = from
    @to = to
    @done = false
    @mutex = Mutex.new

    # If it's a local repository
    if @from.start_with? "/"
      if File.exist? @from
        return
      elsif File.exist? "#{@from}.git" # Bare
        @from = "#{@from}.git"
      else
        throw "Unable to sync '#{@from}"
      end
    end
  end

  def to_s
    "<Source::Single '#{from}' -> '#{to}'>"
  end

  def work(queue)
    @mutex.synchronize { sync! }
  end

  def wait
    loop do
      sleep 0.1
      return if @done
    end
  end

  def sync!
    puts "Sync '#{from}' to '#{to} (dry run: #{dry_run})".blue

    if File.exists?(to) and not File.exists?(File.join(to, "objects"))
      puts "[#{DateTime.now} #{to}] Corrupted, removing!".yellow
      FileUtils.rm_rf(to)
    end

    if not File.exist?(to)
      puts "[#{DateTime.now} #{to}] Cloning ..."
      if not dry_run
        pid = Process.fork {
          Git.clone(from, File.basename(to), path: File.dirname(to), mirror: true)
        }
        Process.waitpid(pid)
      end
    else
      puts "[#{DateTime.now} #{to}] Updating ..."
      if not dry_run
        pid = Process.fork {
          git = Git.bare(to)
          add_remote = true

          # Look for the remove and if it needs to be updated
          git.remotes.each do |remote|
            next if remote.name != "gitsync"

            if remote.url != from
              git.remove_remote("gitsync")
            else
              add_remote = false
              break
            end
          end

          if add_remote
            git.add_remote("gitsync", from, :mirror => 'fetch')
          end

          git.fetch("gitsync")
        }
        Process.waitpid(pid)
      end
    end

    puts "[#{DateTime.now} #{to}] Done ..."
    @done = true
  end
end
