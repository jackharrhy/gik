require "kemal"

require "./gik"

class Gik::Web
  class Site < Gik::Base
    def initialize(@config : Gik::Config, @db : DB::Database)
      Kemal.config.env = "production"

      get "/" do |env|
        "gik"
      end

      get "/image/:uuid/:filename" do |env|
        uuid = env.params.url["uuid"]
        filename = env.params.url["filename"]

        args = [] of DB::Any
        args << uuid.to_s
        args << filename

        res = @db.query_one? "SELECT url FROM art WHERE uuid = ? AND original_filename = ?", args: args, as: String

        res
      end

      post "/upload" do |env|
        HTTP::FormData.parse(env.request) do |upload|
          filename = upload.filename
          next unless filename.is_a? String

          path = Site.valid_path Path[filename]
          next unless path.is_a? Path

          input_path = Site.tmp_path "input", path.extension
          output_path = Site.tmp_path "output", path.extension

          File.open(input_path, "w") do |f|
            IO.copy upload.body, f
          end

          magickify_args = MagickifyArgs.new
          Site.magickify input_path, output_path, magickify_args

          File.delete input_path

          send_file env, output_path.to_s

          File.delete output_path

          uuid = UUID.random
          self_cdn_url = "/#{uuid}/#{filename}"
          # TODO actually store images somewhere

          is_public = env.params.query["public"]?.is_a? String

          user_agent = env.request.headers["User-Agent"]?

          log_web self_cdn_url, filename, is_public, user_agent, uuid
        end
      end
    end

    def run!
      Kemal.run
    end

    def log_web(output_self_cdn_url : String, original_filename : String, is_public : Bool, user_agent : String | Nil, uuid : UUID)
      art_id, art_uuid = log_art output_self_cdn_url, original_filename, is_public, uuid

      args = [] of DB::Any
      args << art_id
      args << user_agent
      @db.exec "INSERT INTO web(art, user_agent) VALUES (?, ?)", args: args
    end
  end
end
