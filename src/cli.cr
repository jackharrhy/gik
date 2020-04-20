require "log"
require "dotenv"

require "./gik"
require "./bot"

backend = Log::IOBackend.new
Log.builder.bind "*", :info, backend

begin
  Dotenv.load
end

Gik::Temp.init

config = Gik::Config.from_env
db = DB.open config.database_url
Gik::Database.init db

bot = Gik::Cord::Bot.new config, db
spawn(bot.run!)

{Signal::INT, Signal::TERM}.each &.trap do
  db.close
  puts "bye"
  exit
end

sleep
