# Larsen Datasupport — Sinatra-app.
# Kjør lokalt: bundle exec ruby app.rb   (eller via config.ru med puma)
ENV["TZ"] = "Europe/Oslo"

require "sinatra/base"
require "sinatra/reloader"
require "date"
require "time"
require "rack/session"
require_relative "db"

class LarsenApp < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  use Rack::Session::Cookie,
      key: "larsen.session",
      secret: ENV.fetch("SESSION_SECRET", "dev-only-secret-change-me-0123456789abcdef0123456789abcdef0123456789abcdef"),
      same_site: :lax,
      expire_after: 7 * 24 * 3600

  set :views, File.join(__dir__, "views")
  set :public_dir, File.join(__dir__, "public")
  set :public_folder, File.join(__dir__, "public")
  set :server, :puma

  CATEGORIES = ["Skjerm", "RAM", "SSD", "Kabel", "Annet"].freeze
  CATEGORY_EMOJI = { "Skjerm" => "🖥️", "RAM" => "🧠", "SSD" => "💽", "Kabel" => "🔌", "Annet" => "📦" }.freeze

  helpers do
    def nav_active(path)
      current = request.path_info
      active = path == "/" ? current == "/" : current.start_with?(path)
      active ? 'class="active"' : ""
    end

    def h(text)
      Rack::Utils.escape_html(text.to_s)
    end

    def js(text)
      text.to_s.gsub("\\", "\\\\").gsub("'", "\\'").gsub("\n", " ")
    end

    # Enkel URL-encoding som er trygg i mailto:-parametere.
    def urlq(text)
      text.to_s.gsub(" ", "%20").gsub("&", "%26").gsub("?", "%3F").gsub("#", "%23")
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

    def blank_nil(value)
      s = value.to_s.strip
      s.empty? ? nil : s
    end

    # Pengehjelpere — alt lagres som heltall øre.
    def format_kr(ore)
      ore = ore.to_i
      return "0 kr" if ore.zero?
      neg = ore < 0
      abs = ore.abs
      kroner = abs / 100
      rest = abs % 100
      txt = kroner.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1 ').reverse
      txt += ",#{format('%02d', rest)}" if rest != 0
      "#{neg ? '−' : ''}#{txt} kr"
    end

    def parse_kr(str)
      return 0 if str.nil? || str.to_s.strip.empty?
      s = str.to_s.strip.gsub(/\s/, "").tr(",", ".")
      return 0 if s.empty?
      (s.to_f * 100).round
    end

    # For utfylling av pris-felt: "850" eller "1 234,50".
    def kr_input(ore)
      ore = ore.to_i
      return "" if ore <= 0
      ore % 100 == 0 ? (ore / 100).to_s : format("%d,%02d", ore / 100, ore % 100)
    end

    def fmt_dt(iso)
      return "–" if iso.nil? || iso.to_s.empty?
      Time.iso8601(iso).localtime.strftime("%d.%m.%Y %H:%M")
    end

    def fmt_date(iso)
      return "–" if iso.nil? || iso.to_s.empty?
      Time.iso8601(iso).localtime.strftime("%d.%m.%Y")
    end

    def fmt_minutes(min)
      min = min.to_i
      return "0 min" if min <= 0
      hh, mm = min.divmod(60)
      hh > 0 ? "#{hh} t #{mm} min" : "#{mm} min"
    end

    def elapsed_display(started_at_iso, now = Time.now)
      return "00:00:00" if started_at_iso.nil? || started_at_iso.to_s.empty?
      diff = [(now - Time.iso8601(started_at_iso)).to_i, 0].max
      hh, rest = diff.divmod(3600)
      mm, ss = rest.divmod(60)
      format("%02d:%02d:%02d", hh, mm, ss)
    end

    def rate_for(row)
      override = row && row["hourly_rate_override"].to_i
      override && override > 0 ? override : setting("default_rate_ore").to_i
    end

    def amount_for_minutes(minutes, rate)
      ((minutes.to_i * rate) / 60.0).round
    end

    def mva_percent
      setting("mva_percent").to_i
    end

    def customers
      db.execute("SELECT * FROM customers ORDER BY name COLLATE NOCASE")
    end

    def active_timer
      db.get_first_row(<<~SQL)
        SELECT te.*, c.name AS customer_name
        FROM time_entries te
        LEFT JOIN customers c ON c.id = te.customer_id
        WHERE te.ended_at IS NULL
        ORDER BY te.id DESC LIMIT 1
      SQL
    end

    def parse_clock(str)
      hh, mm = str.split(":").map(&:to_i)
      [hh.clamp(0, 23), mm.clamp(0, 59)]
    end

    def period_bounds(period)
      today = Date.today
      case period.to_s
      when "today"
        s = Time.local(today.year, today.month, today.day)
        [s.utc.iso8601, (s + 24 * 3600).utc.iso8601]
      when "week"
        monday = today - ((today.wday - 1) % 7)
        s = Time.local(monday.year, monday.month, monday.day)
        [s.utc.iso8601, (s + 7 * 24 * 3600).utc.iso8601]
      else # month
        s = Time.local(today.year, today.month, 1)
        y, m = today.month == 12 ? [today.year + 1, 1] : [today.year, today.month + 1]
        [s.utc.iso8601, Time.local(y, m, 1).utc.iso8601]
      end
    end

    def entries_with_filters(period: nil, customer_id: nil)
      period = "week" unless %w[today week month all].include?(period.to_s)
      where = []
      args = []
      unless period == "all"
        s, e = period_bounds(period)
        where << "te.started_at >= ?"
        where << "te.started_at < ?"
        args.concat([s, e])
      end
      if customer_id && customer_id.to_i > 0
        where << "te.customer_id = ?"
        args << customer_id.to_i
      elsif customer_id == "none"
        where << "te.customer_id IS NULL"
      end
      sql = <<~SQL
        SELECT te.*, c.name AS customer_name, c.hourly_rate_override
        FROM time_entries te
        LEFT JOIN customers c ON c.id = te.customer_id
      SQL
      sql += " WHERE " + where.join(" AND ") unless where.empty?
      sql += " ORDER BY te.started_at DESC"
      rows = db.execute(sql, args)
      rows.each { |r| r["amount_ore"] = amount_for_minutes(r["minutes"], rate_for(r)) }
      totals = {
        minutes: rows.sum { |r| r["minutes"].to_i },
        amount_ore: rows.sum { |r| r["amount_ore"] }
      }
      [rows, totals]
    end

    def new_group(key, customer_name, org_number)
      {
        key: key,
        customer_name: customer_name || "Uten kunde",
        org_number: org_number,
        entries: [], sales: [],
        minutes: 0, time_amount: 0, sale_amount: 0,
        subtotal: 0, mva: 0, total: 0
      }
    end

    def uninvoiced_groups
      entries = db.execute(<<~SQL)
        SELECT te.*, c.name AS customer_name, c.hourly_rate_override, c.org_number
        FROM time_entries te
        LEFT JOIN customers c ON c.id = te.customer_id
        WHERE te.invoiced = 0
        ORDER BY te.started_at
      SQL
      sales = db.execute(<<~SQL)
        SELECT hs.*, hi.name AS item_name, c.name AS customer_name, c.org_number
        FROM hardware_sales hs
        LEFT JOIN hardware_items hi ON hi.id = hs.hardware_item_id
        LEFT JOIN customers c ON c.id = hs.customer_id
        WHERE hs.invoiced = 0
        ORDER BY hs.sold_at
      SQL
      groups = {}
      entries.each do |row|
        key = row["customer_id"] ? row["customer_id"].to_s : "none"
        g = (groups[key] ||= new_group(key, row["customer_name"], row["org_number"]))
        amount = amount_for_minutes(row["minutes"], rate_for(row))
        g[:entries] << row.merge("amount_ore" => amount)
        g[:minutes] += row["minutes"].to_i
        g[:time_amount] += amount
      end
      sales.each do |row|
        key = row["customer_id"] ? row["customer_id"].to_s : "none"
        g = (groups[key] ||= new_group(key, row["customer_name"], row["org_number"]))
        amount = row["quantity"].to_i * row["sale_price_each"].to_i
        g[:sales] << row.merge("amount_ore" => amount)
        g[:sale_amount] += amount
      end
      groups.each_value do |g|
        g[:subtotal] = g[:time_amount] + g[:sale_amount]
        g[:mva] = (g[:subtotal] * mva_percent) / 100
        g[:total] = g[:subtotal] + g[:mva]
      end
      groups
    end

    def next_invoice_ref
      counter = setting("invoice_counter").to_i + 1
      set_setting("invoice_counter", counter.to_s)
      "F-#{Date.today.year}-#{format('%03d', counter)}"
    end

    def recent_invoices
      refs = {}
      db.execute("SELECT DISTINCT invoice_ref, invoiced_at FROM time_entries WHERE invoice_ref IS NOT NULL")
        .each { |r| refs[r["invoice_ref"]] ||= r["invoiced_at"] }
      db.execute("SELECT DISTINCT invoice_ref, invoiced_at FROM hardware_sales WHERE invoice_ref IS NOT NULL")
        .each { |r| refs[r["invoice_ref"]] ||= r["invoiced_at"] }
      refs.sort_by { |_ref, at| at.to_s }.reverse.first(10)
    end

    def invoice_data(ref)
      return nil if ref.to_s.strip.empty?
      ref = ref.to_s.strip
      entries = db.execute(<<~SQL, [ref])
        SELECT te.*, c.name AS customer_name, c.org_number
        FROM time_entries te
        LEFT JOIN customers c ON c.id = te.customer_id
        WHERE te.invoice_ref = ?
        ORDER BY te.started_at
      SQL
      sales = db.execute(<<~SQL, [ref])
        SELECT hs.*, hi.name AS item_name, c.name AS customer_name, c.org_number
        FROM hardware_sales hs
        LEFT JOIN hardware_items hi ON hi.id = hs.hardware_item_id
        LEFT JOIN customers c ON c.id = hs.customer_id
        WHERE hs.invoice_ref = ?
        ORDER BY hs.sold_at
      SQL
      return nil if entries.empty? && sales.empty?
      first = entries.first || sales.first
      rows = []
      entries.each do |r|
        rate = rate_for(r)
        rows << {
          type: "time",
          date: fmt_date(r["started_at"]),
          text: r["description"].to_s,
          detail: fmt_minutes(r["minutes"]),
          rate: rate,
          amount: amount_for_minutes(r["minutes"], rate)
        }
      end
      sales.each do |r|
        amount = r["quantity"].to_i * r["sale_price_each"].to_i
        rows << {
          type: "hardware",
          date: fmt_date(r["sold_at"]),
          text: r["item_name"].to_s,
          detail: "#{r['quantity']} stk × #{format_kr(r['sale_price_each'])}",
          rate: nil,
          amount: amount
        }
      end
      subtotal = rows.sum { |r| r[:amount] }
      {
        ref: ref,
        invoiced_at: first["invoiced_at"],
        customer_name: first["customer_name"] || "Uten kunde",
        org_number: first["org_number"],
        rows: rows,
        subtotal: subtotal,
        mva: (subtotal * mva_percent) / 100,
        total: subtotal + (subtotal * mva_percent) / 100,
        company_name: setting("company_name").to_s,
        company_org: setting("org_number").to_s,
        company_account: setting("account_number").to_s,
        company_vipps: setting("vipps").to_s
      }
    end

    def require_auth!
      pass = ENV["APP_PASSWORD"].to_s
      return if pass.empty? # utvikling: ingen passord → ingen pålogging
      return if authorized?(pass)
      response["WWW-Authenticate"] = %(Basic realm="Larsen Datasupport")
      halt 401, "Tilgang nektet"
    end

    def authorized?(pass)
      auth = Rack::Auth::Basic::Request.new(request.env)
      auth.provided? && auth.basic? && auth.credentials[1] == pass
    end
  end

  before do
    @notice = session.delete(:flash)
    public_path = request.path_info.start_with?("/vare/") || request.path_info == "/health"
    require_auth! unless public_path
  end

  get "/health" do
    content_type :text
    "ok"
  end

  # ── Dashboard ─────────────────────────────────────────────────────────
  get "/" do
    @title = "Oversikt"
    s, e = period_bounds("month")
    month_rows = db.execute(<<~SQL, [s, e])
      SELECT te.*, c.hourly_rate_override
      FROM time_entries te
      LEFT JOIN customers c ON c.id = te.customer_id
      WHERE te.billable = 1 AND te.started_at >= ? AND te.started_at < ?
    SQL
    @month_minutes = month_rows.sum { |r| r["minutes"].to_i }
    @month_amount = month_rows.sum { |r| amount_for_minutes(r["minutes"], rate_for(r)) }
    groups = uninvoiced_groups
    @uninvoiced_subtotal = groups.values.sum { |g| g[:subtotal] }
    @uninvoiced_total = groups.values.sum { |g| g[:total] }
    @customer_count = db.get_first_value("SELECT COUNT(*) FROM customers").to_i
    @stock_count = db.get_first_value("SELECT COALESCE(SUM(quantity_in_stock), 0) FROM hardware_items").to_i
    @active = active_timer

    activity = []
    db.execute("SELECT * FROM time_entries ORDER BY created_at DESC LIMIT 6").each do |r|
      activity << { at: r["created_at"], text: "Timer · #{fmt_dt(r['started_at'])} · #{fmt_minutes(r['minutes'])}#{r['description'].to_s.empty? ? '' : ' · ' + r['description']}" }
    end
    db.execute(<<~SQL).each do |r|
      SELECT hs.*, hi.name AS item_name
      FROM hardware_sales hs
      LEFT JOIN hardware_items hi ON hi.id = hs.hardware_item_id
      ORDER BY hs.created_at DESC LIMIT 6
    SQL
      activity << { at: r["created_at"], text: "Salg · #{fmt_date(r['sold_at'])} · #{r['quantity']}× #{r['item_name']} (#{format_kr(r['quantity'].to_i * r['sale_price_each'].to_i)})" }
    end
    @activity = activity.sort_by { |a| a[:at].to_s }.reverse.first(8)
    erb :dashboard
  end

  # ── Timeregistrering ───────────────────────────────────────────────────
  get "/timer" do
    @title = "Timer"
    @active = active_timer
    @customers = customers
    @entries, @totals = entries_with_filters(period: params[:period], customer_id: params[:customer])
    erb :time_entries
  end

  get "/timer/entries" do
    @entries, @totals = entries_with_filters(period: params[:period], customer_id: params[:customer])
    erb :_entries_table, layout: false
  end

  get "/timer/elapsed" do
    active = active_timer
    halt 204 unless active
    erb :_elapsed_span, layout: false, locals: { active: active }
  end

  post "/timer/start" do
    if active_timer
      session[:flash] = "Det er allerede en aktiv timer — stopp den først."
      redirect "/timer"
    end
    cid = params[:customer_id].to_i
    now = Time.now.utc.iso8601
    db.execute(
      "INSERT INTO time_entries (customer_id, description, started_at, minutes, billable, created_at) VALUES (?, ?, ?, 0, 1, ?)",
      [cid > 0 ? cid : nil, params[:description].to_s.strip, now, now]
    )
    session[:flash] = "Timeren er startet. ⏱️"
    redirect "/timer"
  end

  post "/timer/stop" do
    row = active_timer
    if row
      minutes = [(Time.now - Time.iso8601(row["started_at"])).round / 60, 1].max
      db.execute(
        "UPDATE time_entries SET ended_at = ?, minutes = ? WHERE id = ?",
        [Time.now.utc.iso8601, minutes, row["id"]]
      )
      session[:flash] = "Timeren stoppet: #{fmt_minutes(minutes)} registrert."
    end
    redirect "/timer"
  end

  post "/timer/manual" do
    cid = params[:customer_id].to_i
    desc = params[:description].to_s.strip
    date_s = params[:date].to_s.strip
    start_s = params[:start_time].to_s.strip
    end_s = params[:end_time].to_s.strip
    minutes_param = params[:minutes].to_s.strip
    billable = params[:billable] == "1"

    begin
      d = Date.strptime(date_s, "%Y-%m-%d")
    rescue ArgumentError
      session[:flash] = "Du må fylle inn en gyldig dato."
      redirect "/timer"
    end

    m = nil
    started_at_utc = ended_at_utc = nil
    if minutes_param =~ /\A\d+\z/ && minutes_param.to_i > 0
      m = minutes_param.to_i
      sh, sm = start_s.empty? ? [9, 0] : parse_clock(start_s)
      start_t = Time.local(d.year, d.month, d.day, sh, sm)
      started_at_utc = start_t.utc.iso8601
      ended_at_utc = (start_t + m * 60).utc.iso8601
    elsif !start_s.empty? && !end_s.empty?
      sh, sm = parse_clock(start_s)
      eh, em = parse_clock(end_s)
      start_t = Time.local(d.year, d.month, d.day, sh, sm)
      end_t = Time.local(d.year, d.month, d.day, eh, em)
      end_t += 24 * 3600 if end_t <= start_t # krysser midnatt
      m = ((end_t - start_t) / 60).round
      if m <= 0
        session[:flash] = "Sluttidspunktet må være etter starttidspunktet."
        redirect "/timer"
      end
      started_at_utc = start_t.utc.iso8601
      ended_at_utc = end_t.utc.iso8601
    else
      session[:flash] = "Fyll inn enten varighet i minutter, eller start- og sluttidspunkt."
      redirect "/timer"
    end

    db.execute(<<~SQL, [cid > 0 ? cid : nil, desc, started_at_utc, ended_at_utc, m, billable ? 1 : 0, Time.now.utc.iso8601])
      INSERT INTO time_entries (customer_id, description, started_at, ended_at, minutes, billable, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    SQL
    session[:flash] = "#{fmt_minutes(m)} registrert manuelt."
    redirect "/timer"
  end

  post "/timer/:id/delete" do
    db.execute("DELETE FROM time_entries WHERE id = ?", [params[:id]])
    session[:flash] = "Registreringen er slettet."
    redirect "/timer"
  end

  # ── Faktura ────────────────────────────────────────────────────────────
  get "/faktura" do
    @title = "Faktura"
    @groups = uninvoiced_groups
    @recent = recent_invoices
    erb :invoice_ready
  end

  post "/faktura/mark/:key" do
    key = params[:key]
    ref = next_invoice_ref
    now = Time.now.utc.iso8601
    if key == "none"
      db.execute("UPDATE time_entries SET invoiced = 1, invoice_ref = ?, invoiced_at = ? WHERE invoiced = 0 AND customer_id IS NULL", [ref, now])
      db.execute("UPDATE hardware_sales SET invoiced = 1, invoice_ref = ?, invoiced_at = ? WHERE invoiced = 0 AND customer_id IS NULL", [ref, now])
    else
      db.execute("UPDATE time_entries SET invoiced = 1, invoice_ref = ?, invoiced_at = ? WHERE invoiced = 0 AND customer_id = ?", [ref, now, key.to_i])
      db.execute("UPDATE hardware_sales SET invoiced = 1, invoice_ref = ?, invoiced_at = ? WHERE invoiced = 0 AND customer_id = ?", [ref, now, key.to_i])
    end
    session[:flash] = "Faktura #{ref} opprettet."
    redirect "/faktura/print?ref=#{ref}"
  end

  get "/faktura/print" do
    @invoice = invoice_data(params[:ref])
    halt 404, "Fant ikke fakturaen." unless @invoice
    erb :invoice_print, layout: false
  end

  # ── Hardware-lager ─────────────────────────────────────────────────────
  get "/hardware" do
    @title = "Hardware"
    @items = db.execute("SELECT * FROM hardware_items ORDER BY created_at DESC")
    @customers = customers
    @edit_item = params[:edit].to_i > 0 ? db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:edit].to_i]) : nil
    erb :hardware
  end

  post "/hardware" do
    name = params[:name].to_s.strip
    if name.empty?
      session[:flash] = "Varen må ha et navn."
      redirect "/hardware"
    end
    db.execute(<<~SQL, [name, params[:category], parse_kr(params[:cost_price]), parse_kr(params[:sale_price]), params[:quantity_in_stock].to_i, blank_nil(params[:notes]), Time.now.utc.iso8601])
      INSERT INTO hardware_items (name, category, cost_price, sale_price, quantity_in_stock, notes, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    SQL
    session[:flash] = "Varen er lagt til i lageret."
    redirect "/hardware"
  end

  post "/hardware/:id" do
    halt 404 unless db.get_first_row("SELECT id FROM hardware_items WHERE id = ?", [params[:id]])
    db.execute(<<~SQL, [params[:name].to_s.strip, params[:category], parse_kr(params[:cost_price]), parse_kr(params[:sale_price]), params[:quantity_in_stock].to_i, blank_nil(params[:notes]), params[:id]])
      UPDATE hardware_items SET name = ?, category = ?, cost_price = ?, sale_price = ?, quantity_in_stock = ?, notes = ? WHERE id = ?
    SQL
    session[:flash] = "Varen er oppdatert."
    redirect "/hardware"
  end

  post "/hardware/:id/delete" do
    db.execute("DELETE FROM hardware_items WHERE id = ?", [params[:id]])
    session[:flash] = "Varen er slettet (inkludert salgshistorikk)."
    redirect "/hardware"
  end

  post "/hardware/:id/sell" do
    item = db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:id]])
    halt 404 unless item
    qty = params[:quantity].to_i
    if qty <= 0
      session[:flash] = "Antall må være minst 1."
      redirect "/hardware"
    end
    if qty > item["quantity_in_stock"].to_i
      session[:flash] = "Ikke nok på lager (har #{item['quantity_in_stock']} stk)."
      redirect "/hardware"
    end
    price = parse_kr(params[:sale_price_each])
    price = item["sale_price"].to_i if price <= 0
    cid = params[:customer_id].to_i
    now = Time.now.utc.iso8601
    db.execute(
      "UPDATE hardware_items SET quantity_in_stock = quantity_in_stock - ?, sold_quantity = sold_quantity + ? WHERE id = ?",
      [qty, qty, params[:id]]
    )
    db.execute(
      "INSERT INTO hardware_sales (hardware_item_id, customer_id, quantity, sale_price_each, sold_at, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      [params[:id], cid > 0 ? cid : nil, qty, price, now, now]
    )
    session[:flash] = "Salg registrert: #{qty}× #{item['name']}."
    redirect "/hardware"
  end

  # Offentlig delbar vareside — ingen pålogging.
  get "/vare/:id" do
    @item = db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:id]])
    halt 404, "Fant ikke varen." unless @item
    @company_name = setting("company_name").to_s
    @vipps = setting("vipps").to_s
    @contact_email = setting("contact_email").to_s
    erb :hardware_public, layout: false
  end

  # ── Kunder ─────────────────────────────────────────────────────────────
  get "/kunder" do
    @title = "Kunder"
    @customers = customers
    @edit_customer = params[:edit].to_i > 0 ? db.get_first_row("SELECT * FROM customers WHERE id = ?", [params[:edit].to_i]) : nil
    erb :customers
  end

  post "/kunder" do
    name = params[:name].to_s.strip
    if name.empty?
      session[:flash] = "Kunden må ha et navn."
      redirect "/kunder"
    end
    override = params[:hourly_rate_override].to_s.strip
    db.execute(<<~SQL, [name, blank_nil(params[:org_number]), blank_nil(params[:contact_person]), blank_nil(params[:email]), blank_nil(params[:phone]), override.empty? ? nil : parse_kr(override), blank_nil(params[:notes]), Time.now.utc.iso8601])
      INSERT INTO customers (name, org_number, contact_person, email, phone, hourly_rate_override, notes, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    SQL
    session[:flash] = "Kunden er lagt til."
    redirect "/kunder"
  end

  post "/kunder/:id" do
    override = params[:hourly_rate_override].to_s.strip
    db.execute(<<~SQL, [params[:name].to_s.strip, blank_nil(params[:org_number]), blank_nil(params[:contact_person]), blank_nil(params[:email]), blank_nil(params[:phone]), override.empty? ? nil : parse_kr(override), blank_nil(params[:notes]), params[:id]])
      UPDATE customers SET name = ?, org_number = ?, contact_person = ?, email = ?, phone = ?, hourly_rate_override = ?, notes = ? WHERE id = ?
    SQL
    session[:flash] = "Kunden er oppdatert."
    redirect "/kunder"
  end

  post "/kunder/:id/delete" do
    db.execute("DELETE FROM customers WHERE id = ?", [params[:id]])
    session[:flash] = "Kunden er slettet."
    redirect "/kunder"
  end

  # ── Innstillinger ──────────────────────────────────────────────────────
  get "/innstillinger" do
    @title = "Innstillinger"
    erb :settings
  end

  post "/innstillinger" do
    rate = parse_kr(params[:default_rate_ore])
    set_setting("default_rate_ore", (rate <= 0 ? 85000 : rate).to_s)
    mva = params[:mva_percent].to_i
    set_setting("mva_percent", (mva <= 0 ? 25 : mva).to_s)
    set_setting("company_name", params[:company_name].to_s.strip)
    set_setting("org_number", params[:org_number].to_s.strip)
    set_setting("account_number", params[:account_number].to_s.strip)
    set_setting("vipps", params[:vipps].to_s.strip)
    set_setting("contact_email", params[:contact_email].to_s.strip)
    session[:flash] = "Innstillingene er lagret."
    redirect "/innstillinger"
  end

  run! if __FILE__ == $PROGRAM_NAME
end
