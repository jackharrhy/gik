require "dotenv"

begin
  Dotenv.load
end

require "../src/gik/*"

config = Gik::Config.from_env
db = Gik::Database.init config.database_url

olddb = DB.open "sqlite3://./data/gik.legacy.db"

olddb.query "SELECT * FROM art" do |rs|
  rs.each do
    id = rs.read Int
    message_id = rs.read String
    user_id = rs.read String
    url = rs.read String
    time = rs.read String

    args = [] of DB::Any
    args << UUID.random.to_s
    args << time
    args << url
    args << nil
    args << false

    pp args

    last_row_id = nil
    db.transaction do |tx|
      cnn = tx.connection
      cnn.exec "INSERT INTO art(uuid, time, url, original_filename, public) VALUES (?, ?, ?, ?, ?)", args: args
      last_row_id = cnn.query_one "SELECT last_insert_rowid();", as: Int
    end

    args = [] of DB::Any
    args << last_row_id
    args << message_id
    args << user_id
    args << nil
    pp args
    db.exec "INSERT INTO discord(art, message_id, user_id, guild_id) VALUES (?, ?, ?, ?)", args: args
  end
end
