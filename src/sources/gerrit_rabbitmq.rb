require 'bunny'
require 'colored'

class GitSync::Source::GerritRabbitMQ < GitSync::Source::Gerrit
  attr_reader :rabbitmq_host,
              :rabbitmq_port,
              :exchange,
              :rabbitmq_username,
              :rabbitmq_password

  def initialize(gerrit_host, gerrit_port,
                 username,
                 rabbitmq_host, rabbitmq_port,
                 exchange,
                 rabbitmq_username, rabbitmq_password,
                 from, to, one_shot=false)
    @rabbitmq_host = rabbitmq_host
    @rabbitmq_port = rabbitmq_port
    @exchange = exchange || 'gerrit.publish'
    @rabbitmq_username = rabbitmq_username || 'guest'
    @rabbitmq_password = rabbitmq_password || 'guest'

    super(gerrit_host, gerrit_port, username, from, to, one_shot)
  end

  def stream_events
    puts "[GerritRabbitMQ #{rabbitmq_host}:#{rabbitmq_port}:#{exchange}] Streaming events through rabbitmq (username: #{username})".blue

    connection = Bunny.new(:host => rabbitmq_host,
                           :port => rabbitmq_port,
                           :user => rabbitmq_username,
                           :pass => rabbitmq_password)
    connection.start
    channel = connection.create_channel
    channel.fanout(exchange)
    queue = channel.queue('', exclusive: true)
    queue.bind(exchange)

    queue.subscribe() do |_delivery_info, _properties, body|
      puts "[GerritRabbitMQ #{rabbitmq_host}:#{rabbitmq_port}:#{exchange}] #{body}"
      body.each_line do |line|
        process_event(line) do |event|
          yield(event)
        end
      end
    end

    loop do
        sleep
    end
  end

end

