require "log"
require "dotenv"

require "./gik/*"

backend = Log::IOBackend.new
Log.builder.bind "*", :info, backend

begin
  Dotenv.load
end

Gik::Temp.init

config = Gik::Config.from_env
db = Gik::Database.init config.database_url

bot = Gik::Cord::Bot.new config, db
spawn(bot.run!)

site = Gik::Web::Site.new config, db
spawn(site.run!)

{Signal::INT, Signal::TERM}.each &.trap do
  db.close
  puts "bye"
  exit
end

sleep
