#!/usr/bin/env ruby

$LOAD_PATH << File.dirname(__FILE__)
require 'common'
require 'gerrit_server'
require 'git'
require 'securerandom'

require 'minitest/autorun'
require 'rack/test'

class TestSync < Minitest::Test
  attr_reader :gerrit
  attr_reader :tmpdir

  def setup()
    @tmpdir = Dir.mktmpdir
    puts "Tmpdir: #{tmpdir}"

    ENV['GIT_SSH_COMMAND'] = "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

    @expected_git_sync_ret = 0
  end

  def teardown()
    FileUtils.remove_entry tmpdir

    gerrit.teardown if gerrit
  end

  def setup_gerrit()
    @gerrit = GerritServer.new(name)

    ssh_key = File.read(File.join(ENV['HOME'], ".ssh", "id_rsa.pub"))
    gerrit.add_ssh_key(ssh_key)
  end

  def init_repository(name)
    git = Git.init(File.join(tmpdir, "orig", name))
    git.add_remote("origin", "ssh://#{gerrit.username}@#{gerrit.host}:#{gerrit.ssh_port}/#{name}")
    git.config("user.name", "Test User")
    git.config("user.email", "user@test.com")
    git
  end

  def random_name(length=50)
    (0...length).map { ('a'..'z').to_a[rand(26)] }.join
  end

  def gen_commit(git)
    size = 2 ** 4
    name = random_name

    File.open(File.join(git.dir.path, name), 'wb') do |f|
      size.times { f.write( SecureRandom.random_bytes(size) ) }
    end

    git.add(name)
    git.commit(name)
  end

  def create_gerrit_project(name, nb_commits)
    begin
      gerrit.create_project(name)
    rescue RuntimeError
      puts "Project already exists, reusing"
    end

    git = init_repository(name)

    for i in 0..nb_commits
      gen_commit(git)
    end

    git.push("origin")
    git
  end

  def exec_git_sync(config)
    # Store config
    config_path = File.join(tmpdir, "config.yml")
    File.open(config_path, 'w') { |f| f.write config.to_yaml }

    # Exec
    exec_path = File.expand_path(File.join(File.dirname(__FILE__), '/../git-sync'))
    IO.popen("#{exec_path} #{config_path}") do |io|
      @current_git_sync_pid = io.pid

      if block_given?
        yield
      end

      while line = io.gets
        puts "#{name}: #{line}"
      end

      io.close
      ret = $?.to_i
      puts "#{name}: Exit Code #{ret}"
      assert ret == @expected_git_sync_ret
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
    dest_dir = File.join(tmpdir, "git", "git-sync.git")

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

    # Prepare
    name = random_name
    create_gerrit_project(name, 10)

    dest_dir = File.join(tmpdir, "sync")

    config = {
      'sources' => [
        {
          "type" => "gerrit",
          "oneshot" => true,
          "host" => gerrit.host,
          "port" => gerrit.ssh_port,
          "username" => gerrit.username,
          "to" => dest_dir
        }
      ]
    }

    Timeout.timeout(10) do
      exec_git_sync(config)
    end

    assert File.exist?(File.join(dest_dir, "All-Users.git"))
    assert File.exist?(File.join(dest_dir, "All-Projects.git"))
    assert File.exist?(File.join(dest_dir, "#{name}.git"))
  end

  def wait_for_ref(git_dir, refname, ref)
    Timeout.timeout(20) do
      while true
        if File.exist?(git_dir)
          begin
            sync_git = Git.bare(git_dir)
            if sync_git.object(refname)
              puts sync_git.object(refname).sha
              if sync_git.object(refname).sha == ref
                break
              end
            end
          rescue Git::GitExecuteError
          end

          sleep 1
        end
      end
    end
  end

  def test_sync_gerrit_live_sync()
    setup_gerrit

    # Prepare
    name = random_name(20)
    git = create_gerrit_project(name, 10)

    dest_dir = File.join(tmpdir, "sync")

    config = {
      'sources' => [
        {
          "type" => "gerrit",
          "host" => gerrit.host,
          "port" => gerrit.ssh_port,
          "username" => gerrit.username,
          "to" => dest_dir
        }
      ]
    }

    mutex = Mutex.new
    mutex.lock
    resource = ConditionVariable.new

    thread = Thread.new do
      exec_git_sync(config) do
        resource.signal
      end
    end

    resource.wait(mutex)

    git_orig_ref = git.object('HEAD').sha

    git_sync_dir = File.join(dest_dir, "#{name}.git")

    puts "Waiting for the latest commit to be replicated .. #{git_orig_ref}"
    wait_for_ref(git_sync_dir, 'master', git_orig_ref)

    commit = gen_commit(git)
    ap commit
    git.push("origin")

    new_orig_ref = git.object('HEAD').sha

    # Wait for this new reference to be replicated
    puts "Waiting for the new commit to be replicated .. #{new_orig_ref}"
    wait_for_ref(git_sync_dir, 'master', new_orig_ref)

    @expected_git_sync_ret = 2
    Process.kill("INT", @current_git_sync_pid)
    thread.join
  end
end
