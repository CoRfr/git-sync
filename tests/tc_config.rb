#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__)
require 'common'

require 'minitest/autorun'
require 'rack/test'
require 'base64'

class TestConfig < Minitest::Test

  def setup()
  end

  def teardown()
  end

  def load_test_file(file)
    cfg = GitSync::Config.new
    cfg.load_from_file(File.join(File.dirname(__FILE__), "config/#{file}.yml"))
    cfg
  end

  def test_load_file()
    ["test001", "test002", "test003"].each do |file|
      cfg = load_test_file(file)

      cfg.sources.each do |source|
        ap source
      end
    end
  end

  def test_load_no_source()
    begin
      load_test_file("test004")
    rescue RuntimeError => e
      assert e.message == "No 'sources' section specified in the config file."
    end
  end

  def test_load_wrong_source_type()
    begin
      load_test_file("test005")
    rescue RuntimeError => e
      assert e.message == "Unknown source type 'wrongtype'"
    end
  end
end
