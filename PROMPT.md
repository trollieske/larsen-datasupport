# Den geniale prompten — lim inn i Pi (DeepSeek) i terminalen

Kopier ALT under linjen og lim det inn i `pi` etter du har kjørt `cd larsen-datasupport` og valgt DeepSeek-modellen.

---

Du er en senior Ruby-utvikler som bygger et ekstremt lettvekts, praktisk verktøy for en enkeltmannsbedrift kalt "Larsen Datasupport". Firmaet gjør to ting: (1) fakturerbart IT-supportarbeid på timebasis hos kunder, og (2) selger diverse brukt/nytt hardware (skjermer, RAM, SSD-er, kabler osv.) på siden. Bygg en komplett, kjørbar webapp i Ruby med Sinatra + SQLite (via `sqlite3` gem, ingen ekstern database, ingen Rails). Dette er IKKE en øvelse — generer faktisk kode, faktiske filer, klar til å kjøre med `ruby app.rb` lokalt og deploybar på Fly.io eller Render sin gratis tier.

## Designfilosofi (viktig — følg strengt)
- Færrest mulig avhengigheter. Kun gems: `sinatra`, `sqlite3`, `sinatra-contrib` (for reloading i dev), `puma` som webserver, `rack-protection`. Ingen frontend-rammeverk, ingen npm, ingen build-steg.
- Server-rendered HTML med ERB-templates. Bruk HTMX (én CDN-script-tag, ingen build) for å gjøre knapper/formularer dynamiske uten side-reload — dette gir en SPA-følelse med null JavaScript-kode å skrive selv.
- Responsivt design med ren CSS (ingen Tailwind-build, ingen Bootstrap). Bruk CSS-variabler, `clamp()`, og et enkelt grid/flex-layout som funker like bra på mobil (390px) som desktop (1440px). Mørkt tema som standard siden brukeren jobber tidlig om morgenen og ofte fra mobil i felten.
- Ingen innlogging/brukerhåndtering i v1 — dette er et internt enkeltbruker-verktøy. Beskytt heller hele appen med en enkel HTTP Basic Auth-middleware der passord kommer fra en miljøvariabel (`APP_PASSWORD`), slik at den er trygg å legge ut offentlig på Fly.io/Render uten at fremmede kan taste inn timer.
- Alt skal fungere offline-first i den forstand at SQLite-filen er hele databasen — enkel backup er å kopiere én fil.

## Datamodell
Lag disse tabellene i `schema.sql` og kjør migrering automatisk ved oppstart hvis tabellene ikke finnes:

1. **customers**: id, name, org_number (nullable), contact_person, email, phone, hourly_rate_override (nullable, kroner), notes, created_at.
2. **time_entries**: id, customer_id (FK), description, started_at (datetime), ended_at (datetime, nullable — støtt "pågående timer" med en aktiv timer som kan stoppes), minutes (computed eller lagret ved stopp), billable (boolean, default true), invoiced (boolean, default false), created_at.
3. **hardware_items**: id, name, category (skjerm/RAM/SSD/kabel/annet), cost_price (kroner, hva du betalte), sale_price (kroner, hva du selger for), quantity_in_stock, sold_quantity, notes, created_at.
4. **hardware_sales**: id, hardware_item_id (FK), customer_id (FK, nullable — kan være anonym Finn.no-kunde), quantity, sale_price_each, sold_at, invoiced (boolean).
5. **settings**: key/value-tabell for ting som standard timepris (default 850 kr/t er vanlig norsk IT-supportrate, men gjør det konfigurerbart), mva-sats (25% norsk standard), firmanavn, org.nr, kontonummer/Vipps-nummer for faktura.

## Kjernefunksjonalitet (bygg i denne prioriteringen)

### 1. Timeregistrering (viktigst — bygg først)
- Stor "Start timer"-knapp på forsiden, velg kunde fra dropdown (eller "generisk/internt"), skriv kort beskrivelse. Én knapp-trykk starter en løpende klokke.
- Mens timeren løper: vis live elapsed-time (oppdater med HTMX polling hvert 10. sekund, eller enkel CSS/JS-fri tilnærming med en `<meta refresh>`-lignende HTMX trigger — hold det enkelt, ingen websockets).
- "Stopp timer"-knapp regner ut minutter automatisk og lagrer.
- Manuell registrering også mulig (for når du glemmer å starte timeren): kunde, dato, start/slutt-klokke ELLER bare "antall minutter", beskrivelse.
- Liste over dagens/ukens/månedens timer, filtrerbar per kunde, med sum kroner regnet ut automatisk (minutter/60 × kundens timepris eller standardpris).

### 2. Fakturaberegning
- En side "Klar for fakturering" som viser alle ufakturerte time_entries og hardware_sales gruppert per kunde.
- Knapp "Merk som fakturert" per kunde som setter `invoiced = true` på alt i den gruppen med et faktura-referansenummer og dato.
- Vis regnestykket tydelig: timer × timepris = beløp, + hardware-salg, = subtotal, + mva (25%), = totalbeløp.
- Eksporter til en enkel utskriftsvennlig faktura-visning (egen ERB-view uten navigasjon/CSS-styr, kun ment for "Skriv ut til PDF" via nettleseren — ingen PDF-gem nødvendig, `window.print()`-vennlig CSS med `@media print`).

### 3. Hardware-lager
- Enkel CRUD for hardware_items: legg til vare, kostpris, salgspris, antall på lager.
- "Registrer salg"-knapp som trekker fra lager og logger i hardware_sales, med valgfri kundekobling.
- Oversikt som viser fortjeneste per vare (sale_price - cost_price) × sold_quantity, og total lagerverdi.

### 4. Dashboard (forsiden)
- Denne måneds fakturerbare timer og forventet beløp.
- Ufakturert beløp totalt (timer + hardware) — "penger som ligger og venter".
- Enkel liste "siste aktivitet".

## Ut-av-boksen-idé du skal implementere
Legg til en **"Hurtigmodus for hardware-salg via lenke"**: en offentlig (ikke bak Basic Auth) delbar side per vare, `/vare/:id`, som viser bilde-plassholder, navn, pris og en "Interessert"-knapp som sender deg en enkel mailto: eller viser ditt Vipps-nummer — nyttig når du poster en skjerm på Finn.no eller i en Facebook-gruppe og vil lenke til noe finere enn en tekstmelding. Dette krever ingen ekstra infrastruktur, bare én ekstra route uten auth-middleware.

## Filstruktur å generere
```
larsen-datasupport/
├── app.rb                 # Sinatra-app, alle routes
├── config.ru               # Rack-oppstart for Puma
├── db.rb                    # SQLite-tilkobling + migrering
├── schema.sql
├── Gemfile
├── Gemfile.lock
├── views/
│   ├── layout.erb
│   ├── dashboard.erb
│   ├── timer_active.erb
│   ├── time_entries.erb
│   ├── customers.erb
│   ├── invoice_ready.erb
│   ├── invoice_print.erb
│   ├── hardware.erb
│   └── hardware_public.erb
├── public/
│   └── style.css           # ett samlet stylesheet, mobil-first
├── .env.example
├── fly.toml                 # ferdig konfig for Fly.io gratis-deploy
├── Dockerfile                # multi-stage, ruby:3.3-slim, puma på port 8080
└── README.md                 # kort norsk forklaring: setup, kjøre lokalt, deploye
```

## Konkrete tekniske krav
- Ruby versjon: 3.3.
- Alle kronebeløp lagres som integer øre (avoid float rounding bugs), men vis i UI som kroner med tusenskille og "kr"-suffiks.
- Alle datoer lagres UTC i SQLite, konverteres til Europe/Oslo for visning.
- Skriv `Dockerfile` som binder til `0.0.0.0` og leser `PORT`-env-variabel (Fly/Render setter denne).
- `fly.toml` skal peke på en gratis `shared-cpu-1x`-maskin med `auto_stop_machines = true` og `auto_start_machines = true` slik at appen går i dvale når den ikke brukes (0 kr i praksis på Fly sin gratis allowance).
- Legg inn en `rake`-fri seed-kommando: `ruby db.rb seed` som fyller inn 2-3 testkunder og et par hardware-varer så appen ikke føles tom ved første kjøring.
- Norsk språk i hele UI-en (knapper, labels, feilmeldinger). Kommentarer i koden kan være engelske.

## Leveranse
Generer HVER fil komplett og fungerende, ikke pseudokode og ikke "TODO: implement this". Etter at filene er skrevet, kjør selv `bundle install` og `ruby app.rb` for å verifisere at den starter uten feil, og fiks eventuelle feil du finner før du er ferdig. Til slutt, skriv en kort oppsummering av hvilke kommandoer jeg må kjøre for å (1) starte lokalt, (2) deploye til Fly.io gratis, og (3) sette `APP_PASSWORD`.

---

## Etter at Pi/DeepSeek er ferdig — push til GitHub
```bash
cd larsen-datasupport
git init
git add .
git commit -m "Første versjon av Larsen Datasupport-appen"
git branch -M main
git remote add origin https://github.com/trollieske/larsen-datasupport.git
git push -u origin main
```

## Deploy til Fly.io (gratis)
```bash
curl -L https://fly.io/install.sh | sh
fly auth login
fly launch --now
fly secrets set APP_PASSWORD="ditt-hemmelige-passord"
```
