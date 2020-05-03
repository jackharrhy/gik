require "uri"
require "http/client"

require "discordcr"

require "./gik"

class Gik::Cord
  class Bot < Gik::Base
    def initialize(@config : Gik::Config, @db : DB::Database)
      @client = Discord::Client.new token: @config.token, client_id: @config.client_id
      @cache = Discord::Cache.new @client

      @client.on_message_create do |message|
        begin
          next if !message.content.starts_with? @config.prefix

          result = handle_message message
          @client.create_message message.channel_id, result.message if result.is_a? Result::Error
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

    def self.valid_url(url)
      uri = URI.parse url

      self.valid_path Path[uri.path]
    end

    def log_discord(output_discord_cdn_url : String, original_filename : String, is_public : Bool, message : Discord::Message)
      art_id, art_uuid = log_art output_discord_cdn_url, original_filename, is_public

      channel = @cache.resolve_channel message.channel_id

      guild_id = channel.guild_id
      if guild_id.is_a? Discord::Snowflake
        guild_id = guild_id.to_s
      else
        guild_id = nil
      end

      args = [] of DB::Any
      args << art_id
      args << message.id.to_s
      args << message.author.id.to_s
      args << guild_id
      @db.exec "INSERT INTO discord(art, message_id, user_id, guild_id) VALUES (?, ?, ?, ?)", args: args
    end

    def handle_message(message)
      url = find_url message
      return Result::Error.new "Couldn't find an image :(" unless url.is_a? String

      path = Bot.valid_url url
      return Result::Error.new "Invalid URL, maybe a unknown file extension?" unless path.is_a? Path

      @client.trigger_typing_indicator message.channel_id

      input_path = Bot.tmp_path "input", path.extension
      output_path = Bot.tmp_path "output", path.extension

      HTTP::Client.get(url) do |response|
        File.write input_path, response.body_io
      end

      magickify_args = MagickifyArgs.new
      Bot.magickify input_path, output_path, magickify_args

      File.delete input_path

      sent_message = @client.upload_file(
        channel_id: message.channel_id,
        content: "",
        file: File.open output_path
      )

      File.delete output_path

      output_discord_cdn_url = sent_message.attachments.first.url
      log_discord output_discord_cdn_url, path.basename, false, message

      nil
    end
  end
end
