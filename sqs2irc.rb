require 'aws-sdk'
require 'carrier-pigeon'
require 'json'
require 'yaml'
require 'daemon_spawn'
require 'active_support/core_ext/object/blank'

module IRC
  COLOR_CODE =
  {
    white:   0,
    black:   1,
    blue:    2,
    green:   3,
    red:     4,
    brown:   5,
    purple:  6,
    orange:  7,
    yellow:  8,
    lime:    9,
    teal:    10,
    aqua:    11,
    royal:   12,
    fuchsia: 13,
    grey:    14,
    silver:  15,
  }

  module MessageConverter
    COLOR_PATTERN = /<color([^>]*?)>(.*?)<\/color>(.*)/
    class << self
      def convert(message)
        msg = message.dup
        convert_color!(msg)
        return msg
      end

      private

      def convert_color!(message)
        while (message =~ COLOR_PATTERN)
          color = {}
          attrs = $1.scan(/ ((?:font|bg)="(?:[^"]*?)")/).map! { |a| a[0].split('=') }
          %w(font bg).each do |type|
            val = attrs.detect{ |attr| attr[0] == type }
            color[type] = ::IRC::COLOR_CODE[val[1].delete('"').to_sym] if val
          end
          code = nil
          if color['font']
            code = "\x03%02d" % color['font']
            code += ",%02d" % color['bg'] if color['bg']
            code += ' '
          end
          message.sub!(COLOR_PATTERN, "#{code}\\2#{code ? " \x03" : nil}\\3")
        end
        return message
      end
    end
  end
end

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
      {'notices' => {notice: true}, 'privmsgs' => {}}.each do |type, opt|
        if data[type] && !data[type].empty?
          irc.send(data['channel'],
                   data[type].map { |msgs| msgs.split("\n").map { |msg| IRC::MessageConverter.convert(msg.chomp) } }.flatten,
                   {notice: opt[:notice],
                    nick: data['nick'],
                    host: data['host'],
                    port: data['port']})
        end
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
