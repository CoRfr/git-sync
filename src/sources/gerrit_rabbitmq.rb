require 'bunny'
require 'colored'

class GitSync::Source::GerritRabbitMQ < GitSync::Source::Gerrit
  attr_reader :rabbitmq_host,
              :rabbitmq_port,
              :rabbitmq_exchange,
              :rabbitmq_username,
              :rabbitmq_password,
              :publishers

  def initialize(gerrit_host, gerrit_port,
                 username,
                 from, to,
                 rabbitmq_cfg,
                 one_shot=false,
                 publishers=[])
    @rabbitmq_host = rabbitmq_cfg[:rabbitmq_host]
    @rabbitmq_port = rabbitmq_cfg[:rabbitmq_port]
    @rabbitmq_exchange = rabbitmq_cfg[:rabbitmq_exchange] || 'gerrit.publish'
    @rabbitmq_username = rabbitmq_cfg[:rabbitmq_username] || 'guest'
    @rabbitmq_password = rabbitmq_cfg[:rabbitmq_password] || 'guest'

    super(gerrit_host, gerrit_port, username, from, to, one_shot, publishers)
  end

  def stream_events
    puts "[GerritRabbitMQ #{rabbitmq_host}:#{rabbitmq_port}:#{rabbitmq_exchange}] Streaming events through rabbitmq (rabbitmq_username: #{rabbitmq_username})".blue

    connection = Bunny.new(:host => rabbitmq_host,
                           :port => rabbitmq_port,
                           :user => rabbitmq_username,
                           :pass => rabbitmq_password)
    connection.start
    channel = connection.create_channel
    channel.fanout(rabbitmq_exchange)
    queue = channel.queue('', exclusive: true)
    queue.bind(rabbitmq_exchange)

    queue.subscribe() do |_delivery_info, _properties, body|
      puts "[GerritRabbitMQ #{rabbitmq_host}:#{rabbitmq_port}:#{rabbitmq_exchange}] #{body}"
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

