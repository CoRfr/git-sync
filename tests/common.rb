require "simplecov"
SimpleCov.start

$LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__), '/../src'))
require 'git-sync'
