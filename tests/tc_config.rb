#!/usr/bin/env ruby

$LOAD_PATH << File.expand_path(File.join(File.dirname(__FILE__), '/../src'))
require 'git-sync'

require 'minitest/autorun'
require 'rack/test'
require 'base64'

class TestConfig < Minitest::Test

  def setup()
  end

  def teardown()
  end

  def test_load_file()
    
    ["test001", "test002", "test003"].each do |file|
      cfg = GitSync::Config.new
      cfg.load_from_file(File.join(File.dirname(__FILE__), "config/#{file}.yml"))

      cfg.sources.each do |source|
        ap source
      end
  end
end
