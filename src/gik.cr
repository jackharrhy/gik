require "uuid"

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

    def self.inp_out_paths(extension)
      tmp = Gik::Temp::TMP_DIR
      input_path = Path["#{tmp}input_#{UUID.random}#{extension}"]
      output_path = Path["#{tmp}output_#{UUID.random}#{extension}"]
      {input_path, output_path}
    end

    def self.valid_path(path)
      return unless path.extension != ""
      return unless SUPPORTED_IMAGE_EXTENSIONS.includes? path.extension.downcase
      path
    end

    struct MagickifyArgs
      property width_mod : Float64 = 0.5
      property height_mod : Float64 = 0.5
      property liquid_rescale : Bool = true
      property reverse_mods : Bool = true
    end

    def self.magickify(input_path, output_path, magickify_args)
      channel = Channel(Nil).new
      spawn do
        self.magick do |wand|
          self.magickify wand, input_path, output_path, magickify_args
        end
        channel.send nil
      end
      channel.receive
    end

    def self.magickify(wand, input_path, output_path, args)
      read_image_correctly = LibMagick.magickReadImage(wand, input_path.to_s)
      raise "failed to read image" unless read_image_correctly

      width = LibMagick.magickGetImageWidth(wand) * args.width_mod
      width = 2000 if width > 2000 # clip so not beeg

      height = LibMagick.magickGetImageHeight(wand) * args.height_mod
      height = 2000 if height > 2000 # clip so not beeg

      # liquid rescale based on mods
      if args.liquid_rescale
        rescaled_correctly = LibMagick.magickLiquidRescaleImage wand, width, height, 1, 1
        raise "failed to liquid rescale" unless rescaled_correctly
      end

      # bring back to og size by inverting mods
      if args.reverse_mods
        resized_correctly = LibMagick.magickResizeImage wand, width / args.width_mod, height / args.height_mod, LibMagick::FilterType::LanczosFilter
        raise "failed to resize" unless rescaled_correctly
      end

      wrote_image_correctly = LibMagick.magickWriteImage wand, output_path.to_s
      raise "failed to write image" unless wrote_image_correctly
    end

    abstract def log_art(db_args)
  end
end
