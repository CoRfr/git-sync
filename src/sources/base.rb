class GitSync::Source::Base
  attr_accessor :timeout, :dry_run

  def initialize
    @timeout = 20*60
    @dry_run = false
  end
end
