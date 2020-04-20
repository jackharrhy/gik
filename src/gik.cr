require "sqlite3"
require "db"
require "magickwand-crystal"

module Gik
  class Config
    property token : String = ""
    property client_id : UInt64 = 0_u64
    property prefix : String = ""
    property database_url : String = ""

    def self.from_env
      config = Config.new
      config.token = "Bot #{ENV["GIK_DISCORD_TOKEN"]}"
      config.client_id = ENV["GIK_DISCORD_CLIENT_ID"].to_u64
      config.prefix = ENV["GIK_PREFIX"]
      config.database_url = ENV["GIK_DATABASE_URL"]
      config
    end
  end

  class Database
    def self.init(db)
      db.exec "CREATE TABLE IF NOT EXISTS art (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        url TEXT NOT NULL,
        time INTERGER
      )"
    end
  end

  class Temp
    TMP_DIR = "/tmp/gik/"

    def self.init
      Dir.mkdir_p TMP_DIR
    end
  end

  SUPPORTED_IMAGE_EXTENSIONS = [
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".tga",
    ".bmp",
    ".svg",
  ]

  abstract class Base
    abstract def initialize(@config : Config, @db : DB::Database)

    abstract def run!

    def self.magick
      LibMagick.magickWandGenesis
      wand = LibMagick.newMagickWand
      yield wand
      LibMagick.destroyMagickWand wand
      LibMagick.magickWandTerminus
    end

    def magickify(wand, input_path, output_path, width_mod, height_mod)
      read_image_correctly = LibMagick.magickReadImage(wand, input_path.to_s)
      raise "failed to read image" unless read_image_correctly

      width = LibMagick.magickGetImageWidth(wand) * width_mod
      width = 2000 if width > 2000 # clip so not beeg

      height = LibMagick.magickGetImageHeight(wand) * height_mod
      height = 2000 if height > 2000 # clip so not beeg

      # liquid rescale based on mods
      rescaled_correctly = LibMagick.magickLiquidRescaleImage wand, width, height, 1, 1
      raise "failed to liquid rescale" unless rescaled_correctly

      # bring back to og size by inverting mods
      resized_correctly = LibMagick.magickResizeImage wand, width / width_mod, height / height_mod, LibMagick::FilterType::LanczosFilter
      raise "failed to resize" unless rescaled_correctly

      wrote_image_correctly = LibMagick.magickWriteImage wand, output_path.to_s
      raise "failed to write image" unless wrote_image_correctly
    end

    abstract def log_art(db_args)
  end
end
