require "kemal"

class Gik::Web
  class Site < Gik::Base
    def initialize(@config : Gik::Config, @db : DB::Database)
      Kemal.config.env = "production"

      get "/" do |env|
        "_wip_"
      end

      post "/upload" do |env|
        HTTP::FormData.parse(env.request) do |upload|
          filename = upload.filename
          next unless filename.is_a? String

          path = Site.valid_path Path[filename]
          next unless path.is_a? Path

          input_path, output_path = Site.inp_out_paths path

          File.open(input_path, "w") do |f|
            IO.copy upload.body, f
          end

          magickify_args = MagickifyArgs.new
          Site.magickify input_path, output_path, magickify_args

          File.delete input_path

          send_file env, output_path.to_s

          File.delete output_path

          # TODO log_art
        end
      end
    end

    def run!
      Kemal.run
    end

    def log_art(db_args)
      # TODO
    end
  end
end
