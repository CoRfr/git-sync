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

    git =
      if not File.exist?(to)
        puts "Cloning ..."
        Git.clone(from, File.basename(to), path: File.dirname(to), mirror: true)
      else
        puts "Updating ..."
        Git.open(to)
      end

    git.fetch("origin")
  end

  def schedule
    return [ self ]
  end
end
