# Larsen Datasupport — Sinatra-app.
# Kjør lokalt: bundle exec ruby app.rb   (eller via config.ru med puma)
ENV["TZ"] = "Europe/Oslo"

require "sinatra/base"
require "sinatra/reloader"
require "date"
require "time"
require "securerandom"
require "rack/session"
require "net/smtp"
require "net/http"
require "uri"
require "json"
require "shellwords"
require "openssl"
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

    # Chart-data for dashbord — bar/line-diagram ved inline SVG, ingen CDN.
    def minutes_last_days(n = 14)
      out = []
      today = Date.today
      n.downto(1) do |k|
        d = today - (k - 1)
        s = Time.local(d.year, d.month, d.day).utc.iso8601
        e = (Time.local(d.year, d.month, d.day) + 24 * 3600).utc.iso8601
        mins = db.get_first_value(
          "SELECT COALESCE(SUM(minutes),0) FROM time_entries WHERE started_at >= ? AND started_at < ? AND billable = 1",
          [s, e]
        ).to_i
        out << { label: d.strftime("%d/%m"), short: d.strftime("%a").capitalize[0, 1], value: mins }
      end
      out
    end

    def revenue_last_months(n = 6)
      out = []
      this = Date.today
      n.downto(1) do |k|
        y0, m0 = this.year + ((this.month - k) / 12), ((this.month - k) % 12)
        y0 -= 1 if m0 <= 0; m0 = 12 if m0 <= 0
        y1, m1 = this.year + ((this.month - k + 1) / 12), ((this.month - k + 1) % 12)
        y1 -= 1 if m1 <= 0; m1 = 12 if m1 <= 0
        s = Time.local(y0, m0, 1).utc.iso8601
        e = Time.local(y1, m1, 1).utc.iso8601
        # Fakturert tid + salg pr måned
        mins = db.get_first_value("SELECT COALESCE(SUM(minutes),0) FROM time_entries WHERE started_at >= ? AND started_at < ?", [s, e]).to_i
        time_amt = db.execute(<<~SQL, [s, e]).sum { |r| amount_for_minutes(r["minutes"], rate_for(r)) }
          SELECT te.*, c.hourly_rate_override
          FROM time_entries te LEFT JOIN customers c ON c.id = te.customer_id
          WHERE te.started_at >= ? AND te.started_at < ?
        SQL
        sale_amt = db.get_first_value(
          "SELECT COALESCE(SUM(quantity * sale_price_each),0) FROM hardware_sales WHERE sold_at >= ? AND sold_at < ?",
          [s, e]
        ).to_i
        label = Date.new(y0, m0, 1).strftime("%b")
        out << { label: label, value: time_amt + sale_amt, mins: mins }
      end
      out
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

    def public_path?(path)
      path.start_with?("/vare/", "/upload/", "/butikk", "/login", "/auth/", "/logout", "/min-side") || path == "/health"
    end

    def hx?
      request.env["HTTP_HX_REQUEST"] == "true"
    end

    # E-post-outbox-modellen: alle utsendelser går via tabellen, aldri direkte.
    def queue_email(to, subject, body, kind: "auto", ref: nil)
      db.execute(
        "INSERT INTO emails (to_address, subject, body, kind, ref, status, created_at) VALUES (?, ?, ?, ?, ?, 'queued', ?)",
        [to, subject, body, kind, ref, Time.now.utc.iso8601]
      )
    end

    def save_photo(param)
      return nil unless param && (f = param[:tempfile])
      ext = File.extname(param[:filename].to_s).downcase
      return nil unless %w[.jpg .jpeg .png .webp .gif].include?(ext)
      return nil if f.size > 8 * 1024 * 1024
      name = SecureRandom.hex(8) + ext
      FileUtils.mkdir_p(UPLOADS_DIR)
      IO.copy_stream(f, File.join(UPLOADS_DIR, name))
      name
    end

    def delete_photo(name)
      return unless name && File.file?(File.join(UPLOADS_DIR, name))
      File.delete(File.join(UPLOADS_DIR, name))
    rescue Errno::ENOENT
    end

    def stock_value(item)
      item["cost_price"].to_i * item["quantity_in_stock"].to_i
    end

    def potential_profit(item)
      (item["sale_price"].to_i - item["cost_price"].to_i) * item["quantity_in_stock"].to_i
    end

    def realized_profit(item)
      (item["sale_price"].to_i - item["cost_price"].to_i) * item["sold_quantity"].to_i
    end

    def hardware_stats(items)
      {
        stock_value: items.sum { |i| stock_value(i) },
        potential: items.sum { |i| potential_profit(i) },
        realized: items.sum { |i| realized_profit(i) },
        units: items.sum { |i| i["quantity_in_stock"].to_i }
      }
    end

    def render_cards!
      @items = db.execute("SELECT * FROM hardware_items ORDER BY (quantity_in_stock > 0) DESC, id DESC")
      @stats = hardware_stats(@items)
      @customers = customers
      @base_url = setting("public_base_url").to_s
      @base_url = "#{request.scheme}://#{request.host_with_port}" if @base_url.empty?
      erb :_cards, layout: false
    end

    def ocr_image(path)
      return "" unless path.is_a?(String) && File.file?(path)
      tessdata = File.join(__dir__, "data", "tessdata")
      cmd = Shellwords.join(["tesseract", path, "stdout", "-l", "nor+eng", "--psm", "6"])
      output = nil
      begin
        old = ENV["TESSDATA_PREFIX"]
        ENV["TESSDATA_PREFIX"] = tessdata
        output = `#{cmd}`.to_s
        ENV["TESSDATA_PREFIX"] = old
      rescue StandardError
        return ""
      end
      output.to_s.strip
    end

    def extract_contacts(text)
      return [] if text.to_s.empty?
      email_re = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
      phone_re = /(?:(?:47|0047)[\s-]?)?(?:\d{2}[\s-]?\d{2}[\s-]?\d{2}[\s-]?\d{2}|\d{3}[\s-]?\d{2}[\s-]?\d{3})/
      lines = text.to_s.lines.map(&:strip).reject(&:empty?)
      contacts = []
      pending_name = nil
      lines.each do |line_raw|
        email = line_raw.scan(email_re).first&.to_s&.strip
        phones = line_raw.scan(phone_re).map(&:strip).compact.uniq
        body = line_raw.sub(email_re, "").sub(phone_re, "").gsub(/[•|·:;"]+/, " ").gsub(/\s+/, " ").strip
        words = body.split(/\s+/).reject(&:empty?)
        alldown = words.all? { |w| w =~ /\A[A-ZÆØÅÉÈØÆØÒ]./ }
        name_good = !body.empty? && words.length.between?(1, 4) && alldown

        if email && !name_good && pending_name
          name = pending_name
          body = body.empty? ? name : body
        elsif email && name_good
          name = body
          pending_name = nil
        elsif phones.empty? && !email && name_good && body.split(/[\s,;]+/).length >= 1
          pending_name = body
          next
        elsif email || (!phones.empty? && name_good)
          name = body.empty? ? (pending_name || "") : body
          pending_name = nil
        else
          next
        end
        contacts << { name: name, email: email, phone: phones.first }
      end
      if pending_name && (n = contacts.find { |c| c[:email] && c[:name].to_s.strip.empty? })
        n[:name] = pending_name
      end
      contacts
    end

    def ocr_import(file)
      extract_contacts(ocr_image(file))
    end

    # ── Webshop / innlogging (public) ────────────────────────────────────
    def base_url
      ub = setting("public_base_url").to_s
      return ub unless ub.empty?
      "#{request.scheme}://#{request.host_with_port}"
    end

    def web_user
      return nil unless (id = session[:web_user_id])
      db.get_first_row("SELECT * FROM web_users WHERE id = ?", [id])
    end

    def shop_required!
      return if web_user
      redirect "/login?next=#{URI.encode_www_form_component(request.path_info)}"
    end

    def smtp_configured?
      !setting("smtp_host").to_s.strip.empty?
    end

    def google_enabled?
      !setting("google_client_id").to_s.strip.empty? && !setting("google_client_secret").to_s.strip.empty?
    end

    def issue_magic_token(email)
      token = SecureRandom.urlsafe_base64(32)
      db.execute(
        "INSERT INTO login_tokens (email, token, expires_at, created_at) VALUES (?, ?, ?, ?)",
        [email, token, (Time.now + 30 * 60).utc.iso8601, Time.now.utc.iso8601]
      )
      token
    end

    def consume_magic_token(token)
      row = db.get_first_row(
        "SELECT * FROM login_tokens WHERE token = ? AND used_at IS NULL AND expires_at > ?",
        [token, Time.now.utc.iso8601]
      )
      return nil unless row
      db.execute("UPDATE login_tokens SET used_at = ? WHERE id = ?", [Time.now.utc.iso8601, row["id"]])
      row
    end

    def public_route?(path)
      path.start_with?(
        "/butikk", "/vare/", "/login", "/auth/google", "/logout", "/min-side", "/upload/", "/epost/status"
      ) || public_path?(path)
    end

    # Faktura som tekst (brukes i auto-e-post — ingen PDF-gem nødvendig).
    def invoice_email_body(inv)
      lines = []
      lines << "#{setting('company_name')} — Faktura #{inv[:ref]}"
      lines << "Til: #{inv[:customer_name]}"
      lines << "Dato: #{fmt_date(inv[:invoiced_at])}"
      lines << "-" * 40
      inv[:rows].each do |r|
        lines << "#{r[:date]}  #{r[:text]}  (#{r[:detail]})  #{format_kr(r[:amount])}"
      end
      lines << "-" * 40
      lines << "Sum uten mva: #{format_kr(inv[:subtotal])}"
      lines << "Mva: #{format_kr(inv[:mva])}"
      lines << "TOTALT: #{format_kr(inv[:total])}"
      lines << ""
      lines << "Konto: #{setting('account_number')}" unless setting("account_number").to_s.empty?
      lines << "Vipps: #{setting('vipps')}" unless setting("vipps").to_s.empty?
      pub = setting("public_base_url").to_s
      lines << "Se fakturaen: #{pub}/faktura/print?ref=#{inv[:ref]}" unless pub.empty?
      lines.join("\n")
    end

    def require_auth!
      pass = ENV["APP_PASSWORD"].to_s
      return if pass.empty? # dev: no passord → no auth
      auth = Rack::Auth::Basic::Request.new(request.env)
      auth.provided? && auth.basic? && auth.credentials[1] == pass
    end
  end

  before do
    @notice = session.delete(:flash)
    public_path = public_route?(request.path_info)
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
    @suggestions = dashboard_suggestions
    @days = minutes_last_days(14)
    @months = revenue_last_months(6)
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

    # Auto-e-post: send fakturaen når den opprettes — via outbox (aldri direkte).
    email_to = nil
    if key != "none"
      c = db.get_first_row("SELECT * FROM customers WHERE id = ?", [key.to_i])
      if c
        email_to = c["email"].to_s
        if email_to.empty?
          email_to = db.get_first_value("SELECT email FROM contacts WHERE email != '' AND (customer_id = ? OR name = ?) LIMIT 1", [key.to_i, c["name"]]).to_s
        end
      end
    else
      email_to = db.get_first_value("SELECT email FROM contacts WHERE email != '' AND customer_id IS NULL LIMIT 1").to_s
    end
    if email_to && !email_to.empty?
      inv = invoice_data(ref)
      queue_email(email_to, "Faktura #{ref} fra #{setting('company_name')}", invoice_email_body(inv), kind: "invoice", ref: ref)
      session[:flash] = "Faktura #{ref} opprettet — e-post satt i kø til #{email_to}."
      redirect "/faktura/print?ref=#{ref}"
    else
      session[:flash] = "Faktura #{ref} opprettet. (Ingen e-postadresse funnet på kunden.)"
      redirect "/faktura/print?ref=#{ref}"
    end
  end

  get "/faktura/print" do
    @invoice = invoice_data(params[:ref])
    halt 404, "Fant ikke fakturaen." unless @invoice
    erb :invoice_print, layout: false
  end

  # ── Hardware-lager (kortvegg) ────────────────────────────────────────
  get "/hardware" do
    @title = "Hardware"
    @customers = customers
    @edit_item = params[:edit].to_i > 0 ? db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:edit].to_i]) : nil
    @base_url = setting("public_base_url").to_s
    @base_url = "#{request.scheme}://#{request.host_with_port}" if @base_url.empty?
    @items = db.execute("SELECT * FROM hardware_items ORDER BY (quantity_in_stock > 0) DESC, id DESC")
    @stats = hardware_stats(@items)
    erb :hardware
  end

  get "/hardware/cards" do
    render_cards!
  end

  # Ny vare. Foto er valgfritt. HTMX → oppdater kortveggen uten siderefresh.
  post "/hardware" do
    name = params[:name].to_s.strip
    if name.empty?
      session[:flash] = "Varen må ha et navn."
      return redirect("/hardware") unless hx?
      return erb(:_cards_flash, layout: false)
    end
    photo = save_photo(params[:photo])
    db.execute(<<~SQL, [name, params[:category], photo, parse_kr(params[:cost_price]), parse_kr(params[:sale_price]), params[:quantity_in_stock].to_i, blank_nil(params[:notes]), Time.now.utc.iso8601])
      INSERT INTO hardware_items (name, category, photo, cost_price, sale_price, quantity_in_stock, notes, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    SQL
    session[:flash] = "#{h(name)} er på lageret 🎉"
    return render_cards! if hx?
    redirect "/hardware"
  end

  post "/hardware/:id" do
    item = db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:id]])
    halt 404 unless item
    if params[:photo] && params[:photo][:tempfile]
      new_photo = save_photo(params[:photo])
      delete_photo(item["photo"]) if new_photo
    end
    db.execute(<<~SQL, [params[:name].to_s.strip, params[:category], new_photo || item["photo"], parse_kr(params[:cost_price]), parse_kr(params[:sale_price]), params[:quantity_in_stock].to_i, blank_nil(params[:notes]), params[:id]])
      UPDATE hardware_items SET name = ?, category = ?, photo = ?, cost_price = ?, sale_price = ?, quantity_in_stock = ?, notes = ? WHERE id = ?
    SQL
    session[:flash] = "Varen er oppdatert."
    return render_cards! if hx?
    redirect "/hardware"
  end

  post "/hardware/:id/delete" do
    item = db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:id]])
    halt 404 unless item
    delete_photo(item["photo"])
    db.execute("DELETE FROM hardware_items WHERE id = ?", [params[:id]])
    session[:flash] = "Varen er slettet."
    return render_cards! if hx?
    redirect "/hardware"
  end

  # Salg i tre trykk: kvantum → pris → «Solgt!» (pris er forhåndsutfylt).
  post "/hardware/:id/sell" do
    item = db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:id]])
    halt 404 unless item
    qty = params[:quantity].to_i
    if qty <= 0
      session[:flash] = "Antall må være minst 1."
      return redirect("/hardware") unless hx?
      return erb(:_cards_flash, layout: false)
    end
    if qty > item["quantity_in_stock"].to_i
      session[:flash] = "Ikke nok på lager (har #{item['quantity_in_stock']} stk)."
      return redirect("/hardware") unless hx?
      return erb(:_cards_flash, layout: false)
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
    session[:flash] = "Solgt: #{qty}× #{item['name']} 💸"
    return render_cards! if hx?
    redirect "/hardware"
  end

  # Offentlige bilder til varesidene (og webshop senere).
  get "/upload/:file" do
    file = File.basename(params[:file])
    path = File.join(UPLOADS_DIR, file)
    halt 404 unless file != "." && File.file?(path)
    send_file path
  end

  # Offentlig delbar vareside — webshopprodukt med prisinlogging.
  get "/vare/:id" do
    @item = db.get_first_row("SELECT * FROM hardware_items WHERE id = ?", [params[:id]])
    halt 404, "Fant ikke varen." unless @item
    @company_name = setting("company_name").to_s
    @vipps = setting("vipps").to_s
    @contact_email = setting("contact_email").to_s
    @shop_title = setting("shop_title").to_s
    @logged_in = !!web_user
    @price_shown = @logged_in && @item["sale_price"].to_i > 0
    erb :hardware_public, layout: :layout_public
  end

  # ── Webshop ────────────────────────────────────────────────────────────
  get "/butikk" do
    @title = "Butikk"
    @items = db.execute("SELECT * FROM hardware_items ORDER BY (quantity_in_stock > 0) DESC, id DESC")
    @logged_in = !!web_user
    @shop_title = setting("shop_title").to_s
    @shop_subtitle = setting("shop_subtitle").to_s
    erb :butikk, layout: :layout_public
  end

  get "/login" do
    session[:shop_next] = params[:next] if params[:next]
    @google = google_enabled?
    erb :login, layout: :layout_public
  end

  post "/login/magic" do
    email = params[:email].to_s.strip.downcase
    if email.empty? || email !~ /\A[^@\s]+@[^@\s]+\z/
      session[:shop_flash] = "Skriv inn en gyldig e-postadresse."
      redirect "/login"
    end
    token = issue_magic_token(email)
    link = "#{base_url}/login/magic/#{token}"
    body = <<~TXT
      Hei!

      Trykk på lenken for å logge inn og se prisene i butikken:
      #{link}

      Lenken er gyldig i 30 minutter.
      Vennlig hilsen #{setting('company_name')}
    TXT
    queue_email(email, "Innlogging til #{setting('shop_title')}", body, kind: "magic", ref: token)
    @dev_link = smtp_configured? ? nil : link
    @email = email
    erb :magic_sent, layout: :layout_public
  end

  get "/login/magic/:token" do
    row = consume_magic_token(params[:token])
    if row
      email = row["email"].downcase
      user = db.get_first_row("SELECT * FROM web_users WHERE email = ?", [email])
      unless user
        db.execute(
          "INSERT INTO web_users (email, name, provider, last_login_at, created_at) VALUES (?, ?, 'magic', ?, ?)",
          [email, email.split("@").first, Time.now.utc.iso8601, Time.now.utc.iso8601]
        )
        user = db.get_first_row("SELECT * FROM web_users WHERE email = ?", [email])
      end
      db.execute("UPDATE web_users SET last_login_at = ? WHERE id = ?", [Time.now.utc.iso8601, user["id"]])
      session[:web_user_id] = user["id"]
      next_path = session.delete(:shop_next) || "/butikk"
      redirect next_path
    else
      erb :magic_expired, layout: :layout_public
    end
  end

  get "/auth/google" do
    state = SecureRandom.hex(16)
    session[:oauth_state] = state
    params = {
      client_id: setting("google_client_id"),
      redirect_uri: "#{base_url}/auth/google/callback",
      response_type: "code",
      scope: "openid email profile",
      state: state
    }
    redirect "https://accounts.google.com/o/oauth2/v2/auth?#{URI.encode_www_form(params)}"
  end

  get "/auth/google/callback" do
    halt 400, "Feil state." unless params[:state] && params[:state] == session[:oauth_state]
    halt 400, "Google nektet pålogging." unless params[:code]
    uri = URI("https://oauth2.googleapis.com/token")
    res = Net::HTTP.post_form(uri, {
      code: params[:code],
      client_id: setting("google_client_id"),
      client_secret: setting("google_client_secret"),
      redirect_uri: "#{base_url}/auth/google/callback",
      grant_type: "authorization_code"
    })
    halt 500, "Kunne ikke utveksle Google-kode." unless res.is_a?(Net::HTTPSuccess)
    access = JSON.parse(res.body)["access_token"]
    userinfo = URI("https://openidconnect.googleapis.com/v1/userinfo")
    req = Net::HTTP::Get.new(userinfo)
    req["Authorization"] = "Bearer #{access}"
    info = Net::HTTP.start(userinfo.host, userinfo.port, use_ssl: true) { |http| http.request(req) }
    halt 500, "Kunne ikke hente Google-profil." unless info.is_a?(Net::HTTPSuccess)
    data = JSON.parse(info.body)
    email = (data["email"] || "").downcase
    halt 400, "Google ga ingen e-post." if email.empty?
    user = db.get_first_row("SELECT * FROM web_users WHERE email = ?", [email])
    unless user
      db.execute(
        "INSERT INTO web_users (email, name, provider, google_uid, last_login_at, created_at) VALUES (?, ?, 'google', ?, ?, ?)",
        [email, data["name"] || email.split("@").first, data["sub"], Time.now.utc.iso8601, Time.now.utc.iso8601]
      )
      user = db.get_first_row("SELECT * FROM web_users WHERE email = ?", [email])
    end
    session[:web_user_id] = user["id"]
    redirect session.delete(:shop_next) || "/butikk"
  end

  get "/logout" do
    session.delete(:web_user_id)
    redirect "/butikk"
  end

  get "/min-side" do
    shop_required!
    @user = web_user
    erb :min_side, layout: :layout_public
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
    cid = db.last_insert_row_id
    sync_contact_for_customer(cid)
    session[:flash] = "Kunden er lagt til."
    redirect "/kunder"
  end

  post "/kunder/:id" do
    override = params[:hourly_rate_override].to_s.strip
    db.execute(<<~SQL, [params[:name].to_s.strip, blank_nil(params[:org_number]), blank_nil(params[:contact_person]), blank_nil(params[:email]), blank_nil(params[:phone]), override.empty? ? nil : parse_kr(override), blank_nil(params[:notes]), params[:id]])
      UPDATE customers SET name = ?, org_number = ?, contact_person = ?, email = ?, phone = ?, hourly_rate_override = ?, notes = ? WHERE id = ?
    SQL
    sync_contact_for_customer(params[:id])
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
    set_setting("public_base_url", params[:public_base_url].to_s.strip)
    set_setting("shop_title", params[:shop_title].to_s.strip)
    set_setting("shop_subtitle", params[:shop_subtitle].to_s.strip)
    set_setting("smtp_host", params[:smtp_host].to_s.strip)
    set_setting("smtp_port", params[:smtp_port].to_s.strip)
    set_setting("smtp_user", params[:smtp_user].to_s.strip)
    set_setting("smtp_password", params[:smtp_password].to_s.strip)
    set_setting("smtp_from", params[:smtp_from].to_s.strip)
    set_setting("google_client_id", params[:google_client_id].to_s.strip)
    set_setting("google_client_secret", params[:google_client_secret].to_s.strip)
    session[:flash] = "Innstillingene er lagret."
    redirect "/innstillinger"
  end

  # ── Kontakter (CRM-som-ikke-er-CRM) ────────────────────────────────────
  get "/kontakter" do
    @title = "Kontakter"
    @tag_filter = params[:tag].to_s.strip
    @tags = db.execute("SELECT DISTINCT tags FROM contacts WHERE tags != ''").map { |r| r["tags"].to_s.split(",") }.flatten.map(&:strip).reject(&:empty?).uniq.sort
    @contacts = if @tag_filter.empty?
      db.execute("SELECT c.*, cu.name AS company FROM contacts c LEFT JOIN customers cu ON cu.id = c.customer_id ORDER BY c.name COLLATE NOCASE")
    else
      db.execute("SELECT c.*, cu.name AS company FROM contacts c LEFT JOIN customers cu ON cu.id = c.customer_id WHERE c.tags LIKE ? ORDER BY c.name COLLATE NOCASE", ["%#{@tag_filter}%"])
    end
    @edit_contact = params[:edit].to_i > 0 ? db.get_first_row("SELECT * FROM contacts WHERE id = ?", [params[:edit].to_i]) : nil
    @customers = customers
    erb :kontakter
  end

  post "/kontakter" do
    name = params[:name].to_s.strip
    if name.empty?
      session[:flash] = "Kontakten må ha et navn."
      redirect "/kontakter"
    end
    cid = params[:customer_id].to_i
    db.execute(
      "INSERT INTO contacts (name, email, phone, tags, notes, customer_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      [name, params[:email].to_s.strip, params[:phone].to_s.strip, params[:tags].to_s.strip, params[:notes].to_s.strip, cid > 0 ? cid : nil, Time.now.utc.iso8601]
    )
    session[:flash] = "#{name} er lagt til i kontaktene."
    redirect "/kontakter"
  end

  post "/kontakter/import" do
    content_type :json
    f = params[:file]
    halt 400, { error: "Ingen fil mottatt." }.to_json unless f && f[:tempfile]
    contacts = ocr_import(f[:tempfile].path)
    { contacts: contacts }.to_json
  end

  post "/kontakter/import/text" do
    content_type :json
    contacts = extract_contacts(params[:text].to_s)
    { contacts: contacts }.to_json
  end

  post "/kontakter/commit" do
    content_type :json
    rows = (JSON.parse(request.body.read) rescue {})["contacts"] || []
    added = 0
    skipped = 0
    rows.each do |r|
      name = (r["name"] || "").to_s.strip
      email = (r["email"] || "").to_s.strip.downcase
      next if name.empty?
      existing = email.empty? ? nil : db.get_first_value("SELECT id FROM contacts WHERE email = ?", [email])
      if existing
        skipped += 1
      else
        db.execute(
          "INSERT INTO contacts (name, email, phone, tags, notes, created_at) VALUES (?, ?, ?, ?, ?, ?)",
          [name, email, (r["phone"] || "").to_s.strip, (r["tags"] || "importert").to_s.strip, (r["notes"] || "").to_s.strip, Time.now.utc.iso8601]
        )
        added += 1
      end
    end
    flash = "#{added} lagt til i CRM, #{skipped} fantes allerede."
    session[:flash] = flash
    { added: added, skipped: skipped, flash: flash }.to_json
  end

  post "/kontakter/:id" do
    cid = params[:customer_id].to_i
    db.execute(
      "UPDATE contacts SET name = ?, email = ?, phone = ?, tags = ?, notes = ?, customer_id = ? WHERE id = ?",
      [params[:name].to_s.strip, params[:email].to_s.strip, params[:phone].to_s.strip, params[:tags].to_s.strip, params[:notes].to_s.strip, cid > 0 ? cid : nil, params[:id]]
    )
    session[:flash] = "Kontakten er oppdatert."
    redirect "/kontakter"
  end

  post "/kontakter/:id/delete" do
    db.execute("DELETE FROM contacts WHERE id = ?", [params[:id]])
    session[:flash] = "Kontakten er slettet."
    redirect "/kontakter"
  end

  # ── Auto-sync: opprett/lenk kontakt når kunde opprettes/oppdateres ──
  def sync_contact_for_customer(cid)
    c = db.get_first_row("SELECT * FROM customers WHERE id = ?", [cid])
    return unless c
    email = c["email"].to_s.strip.downcase
    if email.empty?
      return
    end
    contact = db.get_first_row("SELECT id FROM contacts WHERE email = ?", [email])
    if contact
      db.execute("UPDATE contacts SET customer_id = ? WHERE id = ?", [cid, contact["id"]])
    else
      db.execute(
        "INSERT INTO contacts (name, email, phone, tags, notes, customer_id, created_at) VALUES (?, ?, ?, ?, 'Auto fra kunde', ?, ?)",
        [c["name"], c["email"], c["phone"].to_s, "kunde", cid, Time.now.utc.iso8601]
      )
    end
  end

  # ── Dashboard-suggestions: «neste grep» som gjør appen uunnværlig ──
  def dashboard_suggestions
    out = []
    # 1. Ufakturert som venter
    groups = uninvoiced_groups
    if (total = groups.values.sum { |g| g[:total] }) > 0
      top = groups.values.sort_by { |g| g[:total] }.reverse.first(3)
      text = top.map { |g| "#{g[:customer_name]} (#{format_kr(g[:total])})" }.join(", ")
      out << { icon: "🧾", text: "Fakturerbart: #{format_kr(total)} — #{text}", href: "/faktura" }
    end
    # 2. Lavt lager
    low = db.execute("SELECT name FROM hardware_items WHERE quantity_in_stock <= 1 ORDER BY quantity_in_stock LIMIT 3").map { |r| r["name"] }
    unless low.empty?
      out << { icon: "📦", text: "Kjøp inn mer: #{low.join(", ")}", href: "/hardware" }
    end
    # 3. Pågående timer veldig lang
    if (a = active_timer)
      mins = ((Time.now - Time.iso8601(a["started_at"])) / 60).round
      if mins > 480
        out << { icon: "⏱", text: "Timeren har gått i #{fmt_minutes(mins)} — stopp eller noter?", href: "/timer" }
      end
    end
    # 4. Kontakter merket «interessert» til oppfølging (ingen e-post enda)
    now_s = (Time.now - 7 * 24 * 3600).utc.iso8601
    old = db.execute(<<~SQL, [now_s])
      SELECT c.id, c.name FROM contacts c
      LEFT JOIN emails e ON e.to_address = c.email
      WHERE c.tags LIKE '%interessert%' AND c.created_at < ? AND e.id IS NULL
      GROUP BY c.id ORDER BY c.created_at LIMIT 3
    SQL
    unless old.empty?
      out << { icon: "💬", text: "Følg opp: #{old.map { |r| r['name'] }.join(', ')} (interessert, ingen e-post sendt)", href: "/utsendelse" }
    end
    # 5. Gamle varer uten salg → pris-sjekk
    stale = db.execute("SELECT id, name FROM hardware_items WHERE sold_quantity = 0 AND created_at < ? LIMIT 2", [(Time.now - 30 * 24 * 3600).utc.iso8601]).map { |r| r["name"] }
    unless stale.empty?
      out << { icon: "🏷", text: "Har ligget 30+ dager uten salg: #{stale.join(', ')} — sett ned prisen?", href: "/hardware" }
    end
    out.first(5)
  end
  # Tidslinje per kontakt: timer + salg + fakturaer + e-poster samlet.
  get "/kontakter/:id" do
    @title = "Kontakt"
    @contact = db.get_first_row("SELECT * FROM contacts WHERE id = ?", [params[:id]])
    halt 404 unless @contact
    events = []
    if (cid = @contact["customer_id"])
      db.execute("SELECT te.* FROM time_entries te WHERE te.customer_id = ? ORDER BY te.started_at DESC LIMIT 20", [cid]).each do |r|
        events << { at: r["started_at"], icon: "⏱", text: "Timer: #{fmt_minutes(r['minutes'])} — #{r['description']}", sub: fmt_date(r["started_at"]) }
      end
      db.execute("SELECT hs.*, hi.name AS item_name FROM hardware_sales hs LEFT JOIN hardware_items hi ON hi.id = hs.hardware_item_id WHERE hs.customer_id = ? ORDER BY hs.sold_at DESC LIMIT 20", [cid]).each do |r|
        events << { at: r["sold_at"], icon: "💸", text: "Salg: #{r['quantity']}× #{r['item_name']} (#{format_kr(r['quantity'].to_i * r['sale_price_each'].to_i)})", sub: fmt_date(r["sold_at"]) }
      end
      db.execute("SELECT DISTINCT invoice_ref, invoiced_at FROM time_entries WHERE customer_id = ? AND invoice_ref IS NOT NULL UNION SELECT DISTINCT invoice_ref, invoiced_at FROM hardware_sales WHERE customer_id = ? AND invoice_ref IS NOT NULL ORDER BY invoiced_at DESC LIMIT 10", [cid, cid]).each do |r|
        events << { at: r["invoiced_at"], icon: "🧾", text: "Faktura #{r['invoice_ref']}", sub: fmt_date(r["invoiced_at"]) }
      end
    end
    unless @contact["email"].to_s.empty?
      db.execute("SELECT * FROM emails WHERE to_address = ? ORDER BY id DESC LIMIT 20", [@contact["email"]]).each do |r|
        events << { at: r["created_at"], icon: "📧", text: "E-post: #{r['subject']} (#{r['status']})", sub: fmt_dt(r["created_at"]) }
      end
    end
    @events = events.sort_by { |e| e[:at].to_s }.reverse
    erb :kontakt
  end

  # ── E-post (outbox) ────────────────────────────────────────────────────
  get "/epost" do
    @title = "E-post"
    @emails = db.execute("SELECT * FROM emails ORDER BY id DESC LIMIT 100")
    @queued = db.get_first_value("SELECT COUNT(*) FROM emails WHERE status = 'queued'").to_i
    erb :epost
  end

  post "/epost/flush" do
    flush_outbox!
    session[:flash] = "Outboxen er tømt (prøvde å sende alt i kø)."
    redirect "/epost"
  end

  # ── Utsendelse (mailmerge / reklame) ───────────────────────────────────
  get "/utsendelse" do
    @title = "Utsendelse"
    @tags = db.execute("SELECT DISTINCT tags FROM contacts WHERE tags != ''").map { |r| r["tags"].to_s.split(",") }.flatten.map(&:strip).reject(&:empty?).uniq.sort
    @contact_count = db.get_first_value("SELECT COUNT(*) FROM contacts").to_i
    erb :utsendelse
  end

  post "/utsendelse" do
    tag = params[:tag].to_s.strip
    subject = params[:subject].to_s.strip
    body = params[:body].to_s
    if subject.empty? || body.empty?
      session[:flash] = "Du må fylle inn både emne og melding."
      redirect "/utsendelse"
    end
    if tag.empty?
      session[:flash] = "Velg en tag (gruppe) å sende til."
      redirect "/utsendelse"
    end
    contacts = db.execute("SELECT * FROM contacts WHERE tags LIKE ? AND email != ''", ["%#{tag}%"])
    sent = 0
    contacts.each do |c|
      text = body.gsub("{{navn}}", c["name"].to_s)
                .gsub("{{firma}}", (db.get_first_value("SELECT name FROM customers WHERE id = ?", [c["customer_id"]]) if c["customer_id"]).to_s)
                .gsub("{{epost}}", c["email"].to_s)
      queue_email(c["email"], subject.gsub("{{navn}}", c["name"].to_s), text, kind: "mailmerge", ref: "MM-#{Time.now.to_i}")
      sent += 1
    end
    session[:flash] = "#{sent} e-poster satt i kø til gruppen «#{tag}»."
    redirect "/epost"
  end

  run! if __FILE__ == $PROGRAM_NAME
end

# ────────────────────────────────────────────────────────────────────────────
# E-post-outbox: kjører i bakgrunnen og sender alt som står i kø (emails-tabellen).
# Uten SMTP konfigurert logges meldingene til stdout — perfekt for lokal utvikling.
# ────────────────────────────────────────────────────────────────────────────
def mime_message(from, to, subject, body)
  <<~MIME
    From: #{from}
    To: #{to}
    Subject: #{subject}
    MIME-Version: 1.0
    Content-Type: text/plain; charset=UTF-8
    Content-Transfer-Encoding: 8bit

    #{body}
  MIME
end

def send_one_email!(email)
  from = setting("smtp_from").to_s
  from = "#{setting('company_name')} <#{setting('smtp_user')}>" if from.empty?
  host = setting("smtp_host")
  port = setting("smtp_port").to_i
  user = setting("smtp_user").to_s
  pass = setting("smtp_password").to_s
  Net::SMTP.start(host, port, "localhost", user, pass, authtype: :login) do |smtp|
    smtp.send_message(mime_message(from, email["to_address"], email["subject"], email["body"]), from, email["to_address"])
  end
end

def flush_outbox!
  db.execute("SELECT * FROM emails WHERE status = 'queued' ORDER BY id").each do |e|
    begin
      if setting("smtp_host").to_s.strip.empty?
        $stdout.puts "\n[E-POST DEV-MODUS → #{e['to_address']}] Emne: #{e['subject']}\n#{e['body']}\n"
        db.execute("UPDATE emails SET status = 'logged', sent_at = ? WHERE id = ?", [Time.now.utc.iso8601, e["id"]])
      else
        send_one_email!(e)
        db.execute("UPDATE emails SET status = 'sent', sent_at = ?, error = NULL WHERE id = ?", [Time.now.utc.iso8601, e["id"]])
      end
    rescue => ex
      db.execute("UPDATE emails SET status = 'failed', error = ? WHERE id = ?", [ex.message.to_s[0, 500], e["id"]])
    end
  end
end

# Start køkjøreren én gang, uansett hvordan appen startes (dev eller puma/config.ru).
unless defined?(LARSEN_MAILER_THREAD)
  LARSEN_MAILER_THREAD = true
  Thread.new do
    loop do
      sleep 20
      begin
        flush_outbox!
      rescue StandardError
        # Aldri la køkjøreren dø — neste runde prøver igjen.
      end
    end
  end
end
