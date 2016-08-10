
require 'docker'
require 'net/http'

class GerritServer
  attr_reader :name
  attr_reader :container

  def initialize(name)
    @name = name

    if ENV['GERRIT_CONTAINER_ID']
      @container = Docker::Container.get(ENV['GERRIT_CONTAINER_ID'])
    else
      init_new_server
    end
  end

  def init_new_server
    @container ||= Docker::Container.create('Image' => 'openfrontier/gerrit',
                                            'Env' => [ 'AUTH_TYPE=DEVELOPMENT_BECOME_ANY_ACCOUNT' ],
                                            'PublishAllPorts' => true
                                            )

    raise "Unable to create Gerrit container" if not container

    puts "#{name}' => 'Container #{id} created"

    container.start

    puts "#{name}' => 'Container #{id} started"
    
    container.tap(&:start).attach do |stream, chunk|
      if chunk[/Gerrit Code Review .* ready/]
        puts "#{name}' => '#{chunk}"
        return
      end
    end
  end

  def id
    container.id[0..10]
  end

  def teardown
    return if not container

    if ENV['GERRIT_SKIP_TEARDOWN']
      puts "Skipping teardown"
      return
    end

    container.kill!
    puts "#{name}' => 'Container #{id} killed"

    container.remove
    puts "#{name}' => 'Container #{id} removed"
  end

  def desc
    container.json
  end

  def host
    @host ||= desc["NetworkSettings"]["IPAddress"]
  end

  def http_port
    #@http_port ||= desc["NetworkSettings"]["Ports"]["8080/tcp"][0]["HostPort"].to_i
    8080
  end

  def ssh_port
    #@http_port ||= desc["NetworkSettings"]["Ports"]["29418/tcp"][0]["HostPort"].to_i
    29418
  end

  def username
    "admin"
  end

  def login(account_id=1000000)

    # Get GerritAccount cookie
    path = "/login/%23%2F?account_id=#{account_id}"
    req_headers = {}
    req = Net::HTTP::Get.new(path)
    response = Net::HTTP.new(host, http_port).start {|http| http.request(req) }
    if response.code != "302"
      raise "Unable to login"
    end

    @auth_cookie = response.response['set-cookie'][/^(.*);/,1]

    # Get XSRF_TOKEN cookie
    path = "/"
    req_headers["Cookie"] = auth_cookie

    req = Net::HTTP::Get.new(path, initheader=req_headers)
    response = Net::HTTP.new(host, http_port).start {|http| http.request(req) }
    if response.code != "200"
      raise "Unable to login"
    end

    @x_gerrit_auth = response.response['set-cookie'][/^(.*);/,1]
  end

  def auth_cookie
    login if not @auth_cookie
    @auth_cookie
  end

  def x_gerrit_auth
    login if not @x_gerrit_auth
    @x_gerrit_auth[/XSRF_TOKEN=(.*)/, 1]
  end

  def base_headers
    {
      'X-Gerrit-Auth' => x_gerrit_auth,
      'Cookie' => auth_cookie
    }
  end

  def add_ssh_key(ssh_key)
    path = "/accounts/self/sshkeys"
    req = Net::HTTP::Post.new(path, initheader=base_headers)
    req.body = ssh_key
    response = Net::HTTP.new(host, http_port).start {|http| http.request(req) }
    if response.code != "201"
      puts response.code
      puts response.body
      raise "Unable to add the ssh key"
    end
  end

  def create_project(project_name)
    description ||= "Description for '#{project_name}'"

    path = "/projects/#{project_name}"
    message = {
      "name" => project_name
    }

    req_headers = base_headers
    req_headers['Content-Type'] = 'application/json'

    req = Net::HTTP::Put.new(path, initheader=base_headers)
    req.body = message.to_json
    response = Net::HTTP.new(host, http_port).start {|http| http.request(req) }

    if response.code != "201"
      puts response.code
      puts response.body
      raise "Unable to create project #{project_name}"
    end

    JSON.parse(response.body.gsub(")]}'",""))
  end
end
