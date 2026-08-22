-- Larsen Datasupport — databaseskjema.
-- Alle pengebeløp lagres som heltall øre. Alle datoer lagres som UTC ISO-8601-tekst.

CREATE TABLE IF NOT EXISTS customers (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  name                TEXT NOT NULL,
  org_number          TEXT,
  contact_person      TEXT,
  email               TEXT,
  phone               TEXT,
  hourly_rate_override INTEGER,          -- øre/time, NULL = bruk standardpris
  notes               TEXT,
  created_at          TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS time_entries (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id  INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  description  TEXT,
  started_at   TEXT NOT NULL,             -- UTC ISO-8601
  ended_at     TEXT,                      -- NULL = pågående timer
  minutes      INTEGER NOT NULL DEFAULT 0,
  billable     INTEGER NOT NULL DEFAULT 1,
  invoiced     INTEGER NOT NULL DEFAULT 0,
  invoice_ref  TEXT,
  invoiced_at  TEXT,
  created_at   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hardware_items (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  name              TEXT NOT NULL,
  category          TEXT,
  photo             TEXT,
  cost_price        INTEGER NOT NULL DEFAULT 0,   -- øre
  sale_price        INTEGER NOT NULL DEFAULT 0,   -- øre
  quantity_in_stock INTEGER NOT NULL DEFAULT 0,
  sold_quantity     INTEGER NOT NULL DEFAULT 0,
  notes             TEXT,
  created_at        TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS hardware_sales (
  id               INTEGER PRIMARY KEY AUTOINCREMENT,
  hardware_item_id INTEGER REFERENCES hardware_items(id) ON DELETE CASCADE,
  customer_id      INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  quantity         INTEGER NOT NULL DEFAULT 1,
  sale_price_each  INTEGER NOT NULL DEFAULT 0,     -- øre
  sold_at          TEXT NOT NULL,
  invoiced         INTEGER NOT NULL DEFAULT 0,
  invoice_ref      TEXT,
  invoiced_at      TEXT,
  created_at       TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS settings (
  key   TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE IF NOT EXISTS emails (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  to_address   TEXT NOT NULL,
  subject      TEXT NOT NULL,
  body         TEXT NOT NULL,
  kind         TEXT NOT NULL DEFAULT 'auto',   -- invoice | magic | mailmerge | welcome
  ref          TEXT,
  status       TEXT NOT NULL DEFAULT 'queued', -- queued | sent | failed | logged
  error        TEXT,
  sent_at      TEXT,
  created_at   TEXT NOT NULL
);

-- CRM-som-ikke-er-CRM: kontakter (kunder + leads) med tags og tidslinje.
CREATE TABLE IF NOT EXISTS contacts (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  name        TEXT NOT NULL,
  email       TEXT,
  phone       TEXT,
  tags        TEXT,              -- kommaseparert
  notes       TEXT,
  customer_id INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  created_at  TEXT NOT NULL
);

-- Webshop-brukere (magic link eller Google).
CREATE TABLE IF NOT EXISTS web_users (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  email        TEXT NOT NULL UNIQUE,
  name         TEXT,
  provider     TEXT NOT NULL DEFAULT 'magic',  -- magic | google
  google_uid   TEXT,
  last_login_at TEXT,
  created_at   TEXT NOT NULL
);

-- Magiske innloggingslenker (én bruk, utløper).
CREATE TABLE IF NOT EXISTS login_tokens (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  email       TEXT NOT NULL,
  token       TEXT NOT NULL,
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  created_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_time_entries_customer   ON time_entries(customer_id);
CREATE INDEX IF NOT EXISTS idx_time_entries_invoiced   ON time_entries(invoiced);
CREATE INDEX IF NOT EXISTS idx_hardware_sales_item     ON hardware_sales(hardware_item_id);
CREATE INDEX IF NOT EXISTS idx_hardware_sales_customer ON hardware_sales(customer_id);
