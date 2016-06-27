require 'colored'
require 'git'

class GitSync::Source::Single
  attr_reader :from, :to

  def initialize(from, to)
    @from = from
    @to = to
  end

  def sync!(dry_run=false)
    puts "Sync '#{from}' to '#{to}".yellow

    return if dry_run

    if not File.exist?(to)
      puts "[#{to}] Cloning ..."
      Git.clone(from, File.basename(to), path: File.dirname(to), mirror: true)
    else
      puts "[#{to}] Updating ..."
      git = Git.open(to, bare: true)
      git.fetch("origin")
    end

    puts "[#{to}] Done ..."
  end

  def schedule
    return [ self ]
  end
end
