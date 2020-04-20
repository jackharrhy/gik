require "uri"
require "uuid"
require "http/client"

require "discordcr"

class Gik::Cord
  class Bot < Gik::Base
    def initialize(@config : Gik::Config, @db : DB::Database)
      @client = Discord::Client.new token: @config.token, client_id: @config.client_id
      @cache = Discord::Cache.new @client

      @client.on_message_create do |message|
        begin
          next if !message.content.starts_with? @config.prefix
          handle_message message
        rescue ex
          oops = ex.inspect_with_backtrace
          puts oops
          @client.create_message message.channel_id, "```#{oops}```"
        end
      end
    end

    def run!
      @client.run
    end

    def self.url_from_message(message)
      if message.embeds.size > 0
        embed = message.embeds.first
        if embed.type == "image"
          return embed.url if embed.url.is_a? String
        end
      end

      if message.attachments.size > 0
        return message.attachments.first.url
      end
    end

    def find_url(message)
      url = Bot.url_from_message message

      if !url.is_a? String
        @client.get_channel_messages(message.channel_id, 20).each do |historical_message|
          url = Bot.url_from_message historical_message
          break if url.is_a? String
        end
      end

      url
    end

    def self.valid_path(url)
      uri = URI.parse url

      path = Path[uri.path]
      return unless path.extension != ""
      return unless SUPPORTED_IMAGE_EXTENSIONS.includes? path.extension

      path
    end

    def log_art(output_discord_cdn_url, message)
      args = [] of DB::Any
      args << message.id.to_s
      args << message.author.id.to_s
      args << output_discord_cdn_url
      args << Time.utc
      log_art args
    end

    def log_art(db_args)
      @db.exec "INSERT INTO art(message_id, user_id, url, time) VALUES (?, ?, ?, ?)", args: db_args
    end

    def handle_message(message)
      url = find_url message
      return unless url.is_a? String

      path = Bot.valid_path url
      return unless path.is_a? Path

      @client.trigger_typing_indicator message.channel_id

      tmp = Gik::Temp::TMP_DIR
      input_path = Path["#{tmp}input_#{UUID.random}#{path.extension}"]
      output_path = Path["#{tmp}output_#{UUID.random}#{path.extension}"]

      HTTP::Client.get(url) do |response|
        File.write input_path, response.body_io
      end

      mod = 0.5
      width_mod = mod
      height_mod = mod

      Bot.magick do |wand|
        magickify wand, input_path, output_path, width_mod, height_mod
      end

      File.delete input_path

      sent_message = @client.upload_file(
        channel_id: message.channel_id,
        content: "",
        file: File.open output_path
      )

      File.delete output_path

      output_discord_cdn_url = sent_message.attachments.first.url
      log_art output_discord_cdn_url, message
    end
  end
end
