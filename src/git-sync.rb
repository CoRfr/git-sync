require 'git'

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

module GitSync
  module Source
  end
end

require 'config.rb'

require 'sources/single.rb'
require 'sources/gerrit.rb'
