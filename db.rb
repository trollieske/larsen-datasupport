# Larsen Datasupport — SQLite-tilkobling, migrering og seeding.
# Ingen ORM: rå SQL og én fil som hele databasen. Backup = kopier data/larsen.db.
ENV["TZ"] ||= "Europe/Oslo"

require "sqlite3"
require "fileutils"
require "time"

DB_PATH = ENV.fetch("DATABASE_PATH", File.join(__dir__, "data", "larsen.db"))

def db
  @db ||= begin
    FileUtils.mkdir_p(File.dirname(DB_PATH))
    db = SQLite3::Database.new(DB_PATH)
    db.results_as_hash = true
    db.busy_timeout = 5000
    db.execute("PRAGMA journal_mode = WAL")
    db.execute("PRAGMA foreign_keys = ON")
    db
  end
end

def setting(key)
  row = db.get_first_row("SELECT value FROM settings WHERE key = ?", [key.to_s])
  row ? row["value"] : nil
end

def set_setting(key, value)
  db.execute(
    "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
    [key.to_s, value.to_s]
  )
end

def ensure_column(table, column, ddl)
  cols = db.execute("PRAGMA table_info(#{table})").map { |r| r["name"] }
  db.execute("ALTER TABLE #{table} ADD COLUMN #{column} #{ddl}") unless cols.include?(column)
end

def migrate!
  db.execute_batch(File.read(File.join(__dir__, "schema.sql")))

  # Kolonner lagt til etter første versjon — trygge for eksisterende databaser.
  ensure_column("time_entries", "invoice_ref", "TEXT")
  ensure_column("time_entries", "invoiced_at", "TEXT")
  ensure_column("hardware_sales", "invoice_ref", "TEXT")
  ensure_column("hardware_sales", "invoiced_at", "TEXT")

  defaults = {
    "default_rate_ore" => "85000",  # 850 kr/time — standard norsk IT-supportrate
    "mva_percent" => "25",
    "company_name" => "Larsen Datasupport",
    "org_number" => "",
    "account_number" => "",
    "vipps" => "",
    "contact_email" => "",
    "invoice_counter" => "0"
  }
  defaults.each { |k, v| set_setting(k, v) unless setting(k) }
end

def seed!
  migrate!
  if db.get_first_value("SELECT COUNT(*) FROM customers").to_i.zero?
    now = Time.now.utc.iso8601
    db.execute(
      "INSERT INTO customers (name, org_number, contact_person, email, phone, notes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ["Berg & Dahl Regnskap AS", "912345678", "Kari Berg", "kari@bergdahl.no", "22 44 55 66", "Faste timer hver tirsdag.", now]
    )
    db.execute(
      "INSERT INTO customers (name, org_number, contact_person, email, phone, notes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ["Solheim Maskin AS", "987654321", "Ole Solheim", "ole@solheim.no", "99 88 77 66", "Godt kundeforhold siden 2021.", now]
    )
    db.execute(
      "INSERT INTO customers (name, org_number, contact_person, email, phone, notes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      ["Fjordveien Borettslag", nil, "Elin Hansen", "elin@fjordveien.no", "33 22 11 00", "Månedlig drift av fellesnettverket.", now]
    )
    puts "  → 3 testkunder opprettet"
  end

  if db.get_first_value("SELECT COUNT(*) FROM hardware_items").to_i.zero?
    now = Time.now.utc.iso8601
    items = [
      ["Dell P2422H 24\" skjerm",        "Skjerm", 1_100_00, 1_650_00, 3, "Brukt, nesten som ny. Ingen skjermfeil."],
      ["Samsung 970 EVO Plus 1 TB SSD",  "SSD",      700_00,   999_00, 5, "Nytt, uåpnet eske."],
      ["Kingston 16 GB DDR4-3200",       "RAM",      350_00,   549_00, 4, "Dual-rank, fungerer på de fleste hovedkort."],
      ["HDMI-kabel 2 m",                 "Kabel",     45_00,    89_00, 10, ""]
    ]
    items.each do |i|
      db.execute(
        "INSERT INTO hardware_items (name, category, cost_price, sale_price, quantity_in_stock, notes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
        [i[0], i[1], i[2], i[3], i[4], i[5], now]
      )
    end
    puts "  → 4 testvarer opprettet"
  end

  puts "Seed ferdig. Database: #{DB_PATH}"
end

# Kjør alltid migrering ved oppstart (også når appen lastes inn via app.rb).
migrate!

if File.basename($PROGRAM_NAME) == "db.rb" && ARGV.first == "seed"
  seed!
end
