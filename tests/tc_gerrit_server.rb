#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__)
require 'common'
require 'gerrit_server'

require 'minitest/autorun'
require 'rack/test'

class TestGerritSync < Minitest::Test
  attr_reader :gerrit

  def setup()
    puts "Docker: #{Docker.version}"
    @gerrit = GerritServer.new(name)
  end

  def teardown()
    gerrit.teardown if gerrit
  end

  def test_desc()
    assert gerrit.desc
  end

  def test_network()
    puts "Host: #{gerrit.host}"
    assert gerrit.host

    puts "HTTP: #{gerrit.http_port}"
    assert gerrit.http_port > 0

    puts "SSH: #{gerrit.ssh_port}"
    assert gerrit.ssh_port > 0
  end

  def test_login()
    gerrit.login
  end

  def test_capabilities()
    gerrit.capabilities
  end

  def test_add_ssh_key()
    ssh_key = File.read(File.join(ENV['HOME'], ".ssh", "id_rsa.pub"))
    gerrit.add_ssh_key(ssh_key)

    # Connect through SSH
    IO.popen("ssh -p #{gerrit.ssh_port} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no #{gerrit.username}@#{gerrit.host} gerrit version") do |io|
      while line = io.gets
        puts "#{name}: #{line}"
      end

      io.close
      ret = $?.to_i
      puts "#{name}: Exit Code #{ret}"
      assert ret == 0
    end
  end

  def test_create_project()
    project_name = "test"
    project = gerrit.create_project(project_name)

    assert project["id"] == project_name
  end

end