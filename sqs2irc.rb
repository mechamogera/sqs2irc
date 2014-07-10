require 'aws-sdk'
require 'carrier-pigeon'
require 'json'
require 'yaml'
require 'daemon_spawn'

class IRCSender
  def initialize(host, port, nick, default_channel)
    @host, @port, @nick, @default_channel = host, port, nick, default_channel
  end

  def send(channel, messages, opts = {})
    opts[:host] ||= @host
    opts[:port] ||= @port
    opts[:nick] ||= @nick
    opts[:notice] ||= false

    pigeon = CarrierPigeon.new(host: opts[:host],
                               port: opts[:port],
                               nick: opts[:nick],
                               channel: channel || @default_channel ,
                               join: true)
    messages.each do |message|
      pigeon.message(channel || @default_channel, message, opts[:notice])
    end

    pigeon.die
  end
end

module SQS2IRC
  def self.start(opts)
    sqs = AWS::SQS.new(access_key_id: opts["aws"]["access_key_id"],
                       secret_access_key: opts["aws"]["secret_access_key"],
                       proxy_uri: ENV['HTTP_PROXY'] || ENV['http_proxy'],
                       region: opts["aws"]["region"])
    queue = sqs.queues.named(opts["aws"]["sqs_name"])
    irc = IRCSender.new(opts['irc']['host'], opts['irc']['port'], opts['irc']['nick'], opts['irc']['default_channel'])

    queue.poll(wait_time_seconds: nil) do |msg|
      data = JSON.parse(msg.as_sns_message.body) rescue {'notices' => [msg.as_sns_message.body]}
      if data['notices'] && !data['notices'].empty?
        irc.send(data['channel'], 
                 data['notices'].map { |notice| notice.split("\n").map { |msg| msg.chomp } }.flatten, 
                 {notice: true, 
                  nick: data['nick'],
                  host: data['host'],
                  port: data['port']})
      end
      if data['privmsgs'] && !data['privmsgs'].empty?
        irc.send(data['channel'], 
                 data['privmsgs'].map { |notice| notice.split("\n").map { |msg| msg.chomp } }.flatten,
                 {nick: data['nick'],
                  host: data['host'],
                  port: data['port']})
      end
    end
  rescue => e
    irc.send(nil, [e.message], true) if irc rescue nil
    raise e
  end
end

class SQS2IRCDaemon < DaemonSpawn::Base
  def start(args)
    puts "start : #{Time.now}"
    SQS2IRC.start(YAML.load_file(File.expand_path(File.join(File.dirname(__FILE__), 'conf', "#{File.basename(__FILE__, ".*")}.yml"))))
  end

  def stop
    puts "stop : #{Time.now}"
  end
end

SQS2IRCDaemon.spawn!({
  working_dir: File.expand_path(File.dirname(__FILE__)),
  pid_file: File.expand_path(File.join(File.dirname(__FILE__), 'tmp', "#{File.basename(__FILE__, ".*")}.pid")),
  log_file: File.expand_path(File.join(File.dirname(__FILE__), 'log', "#{File.basename(__FILE__, ".*")}.log")),
  sync_log: true,
  singleton: true
})
