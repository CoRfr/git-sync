#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__)
require 'common'
require 'gerrit_server'

require 'minitest/autorun'
require 'rack/test'

class TestSync < Minitest::Test
  attr_reader :gerrit

  def setup()
    @syncdir = Dir.mktmpdir
    puts "Tmpdir: #{@syncdir}"
  end

  def teardown()
    FileUtils.remove_entry @syncdir

    gerrit.teardown if gerrit
  end

  def setup_gerrit()
    @gerrit = GerritServer.new(name)

    ssh_key = File.read(File.join(ENV['HOME'], ".ssh", "id_rsa.pub"))
    gerrit.add_ssh_key(ssh_key)
  end

  def exec_git_sync(config)
    # Store config
    config_path = File.join(@syncdir, "config.yml")
    File.open(config_path, 'w') { |f| f.write config.to_yaml }

    # Exec
    exec_path = File.expand_path(File.join(File.dirname(__FILE__), '/../git-sync'))
    IO.popen("#{exec_path} #{config_path}") do |io|
      while line = io.gets
        puts "#{name}: #{line}"
      end

      io.close
      ret = $?.to_i
      puts "#{name}: Exit Code #{ret}"
      assert ret == 0
    end
  end

  def test_simple_event()
    src = GitSync::Source::Gerrit.new("gerrit", 29418, nil, "from", "to")

    line = '{"author":{"name":"Jenkins","email":"jenkins@sierrawireless.com","username":"jenkins"},"comment":"Patch Set 3:\n\nBuild Successful \n\nhttp://jenkins/job/Legato-Merged/104/ : SUCCESS","patchSet":{"number":"3","revision":"8ddc03b9be017ed3ab17f56bfea6272cc92dc4c2","parents":["16211caa7b58b0365dd28e7d9353d54c64751e13"],"ref":"refs/changes/55/7755/3","uploader":{"name":"Gildas Seimbille","email":"gseimbille@sierrawireless.com","username":"gseimbille"},"createdOn":1467037232,"author":{"name":"Gildas Seimbille","email":"gseimbille@sierrawireless.com","username":"gseimbille"},"isDraft":false,"kind":"REWORK","sizeInsertions":32,"sizeDeletions":-23},"change":{"project":"Legato/platformAdaptor/at","branch":"master","id":"I2e5354f13d1ad71102d5b34b2d8e43b69c56d501","number":"7755","subject":"[RasPi] Fix PA AT initialization","owner":{"name":"Gildas Seimbille","email":"gseimbille@sierrawireless.com","username":"gseimbille"},"url":"https://gerrit/7755","commitMessage":"[RasPi] Fix PA AT initialization\n\nFix a little problem in the AT platform adaptor initialization.\n(functions were not in the right order)\n\nResolves: LE-5294\nChange-Id: I2e5354f13d1ad71102d5b34b2d8e43b69c56d501\n","status":"MERGED"},"type":"comment-added","eventCreatedOn":1467039668}
'
    got_line = false
    src.process_event(line) do |event|
      got_line = true
    end

    assert got_line
  end

  def test_sync_github()
    dest_dir = File.join(@syncdir, "git", "git-sync.git")

    config = {
      'sources' => [
        {
          "from" => 'https://github.com/CoRfr/git-sync.git',
          "to" => dest_dir
        }
      ]
    }

    exec_git_sync(config)
    assert File.exist?(dest_dir)
  end

  def test_sync_gerrit_one_shot()
    setup_gerrit

    gerrit.create_project("test-project")
  end
end
