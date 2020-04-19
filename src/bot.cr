require "uri"
require "uuid"
require "log"
require "http/client"

require "sqlite3"
require "db"
require "dotenv"
require "discordcr"
require "magickwand-crystal"

backend = Log::IOBackend.new
Log.builder.bind "*", :info, backend

begin
  Dotenv.load
end

TMP = "/tmp/gik/"
Dir.mkdir_p TMP

SUPPORTED_IMAGE_EXTENSIONS = [
  ".png",
  ".jpg",
  ".jpeg",
  ".gif",
  ".tga",
  ".bmp",
  ".svg",
  ".psd",
]

TOKEN     = "Bot #{ENV["GIK_DISCORD_TOKEN"]}"
CLIENT_ID = ENV["GIK_DISCORD_CLIENT_ID"].to_u64
PREFIX    = ENV["GIK_PREFIX"]
DATABASE_URL = ENV["GIK_DATABASE_URL"]

client = Discord::Client.new(token: TOKEN, client_id: CLIENT_ID)
cache = Discord::Cache.new(client)

db = DB.open DATABASE_URL

db.exec "CREATE TABLE IF NOT EXISTS art (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  url TEXT NOT NULL,
  time INTERGER
)"

def magick
  LibMagick.magickWandGenesis
  wand = LibMagick.newMagickWand
  yield wand
  LibMagick.destroyMagickWand wand
  LibMagick.magickWandTerminus
end

def url_from_message(message)
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

client.on_message_create do |message|
  begin
    next if !message.content.starts_with? PREFIX

    url = url_from_message message

    if !url.is_a? String
      client.get_channel_messages(message.channel_id, 20).each do |historical_message|
        url = url_from_message historical_message
        break if url.is_a? String
      end
    end

    next unless url.is_a? String

    uri = URI.parse url
    path = Path[uri.path]
    next unless path.extension != ""
    next unless SUPPORTED_IMAGE_EXTENSIONS.includes? path.extension

    client.trigger_typing_indicator message.channel_id

    input_path = Path["#{TMP}input_#{UUID.random}#{path.extension}"]
    output_path = Path["#{TMP}output_#{UUID.random}#{path.extension}"]

    HTTP::Client.get(url) do |response|
      File.write input_path, response.body_io
    end

    mod = 0.5
    width_mod = mod
    height_mod = mod

    magick do |wand|
      if LibMagick.magickReadImage(wand, input_path.to_s)
        width = LibMagick.magickGetImageWidth(wand) * width_mod
        width = 2000 if width > 2000

        height = LibMagick.magickGetImageHeight(wand) * height_mod
        height = 2000 if height > 2000

        # liquid rescale half size
        LibMagick.magickLiquidRescaleImage wand, width, height, 1, 1

        # bring back to og size by inverting mod
        LibMagick.magickResizeImage wand, width / mod, height / mod, LibMagick::FilterType::LanczosFilter

        LibMagick.magickWriteImage wand, output_path.to_s
      end
    end

    File.delete input_path

    sent_message = client.upload_file(
      channel_id: message.channel_id,
      content: "",
      file: File.open output_path
    )

    File.delete output_path

    output_discord_cdn_url = sent_message.attachments.first.url
    args = [] of DB::Any
    args << message.id.to_s
    args << message.author.id.to_s
    args << output_discord_cdn_url
    args << Time.utc
    db.exec "INSERT INTO art(message_id, user_id, url, time) VALUES (?, ?, ?, ?)", args: args
  rescue ex
    oops = ex.inspect_with_backtrace
    puts oops
    client.create_message message.channel_id, "```#{oops}```"
  end
end

client.run
