# Larsen Datasupport

Internt verktøy for timeregistrering, fakturaberegning og hardware-lager — bygget for énmannsbedriften Larsen Datasupport (IT-support på timebasis + salg av brukt/ny hardware).

Ekstremt lettvekt: **Sinatra + SQLite + ERB + HTMX**. Ingen Rails, ingen npm, ingen build-steg. Hele databasen er én fil (`data/larsen.db`).

## Funksjoner (v1)

- **Timeregistrering** — én-knapps start/stopp-timer per kunde med live nedtelling (HTMX-polling), pluss manuell registrering (minutter eller start/slutt-tid). Lister for dag/uke/måned, filtrerbar per kunde, med automatisk krone-sum.
- **Fakturaberegning** — «Klar for fakturering» grupperer ufakturerte timer og hardware-salg per kunde, viser regnestykket (timer × pris + salg = subtotal, + 25 % mva = total), og lager en utskriftsvennlig faktura (nettleserens «Skriv ut → Lagre som PDF», ingen PDF-gem).
- **Hardware-lager** — CRUD for varer, salgsregistrering som trekker på lageret, fortjeneste per vare og total lagerverdi.
- **Delbar vareside** — hver vare har en offentlig side `/vare/:id` (uten pålogging) med pris og «Interessert»-knapp (mailto: / Vipps) — perfekt når du linker fra Finn.no eller Facebook.
- **Dashboard** — månedens fakturerbare timer og forventet beløp, ufakturert beløp («penger som ligger og venter») og siste aktivitet.
- **Innstillinger** — standard timepris (standard 850 kr/t), mva-sats, firmanavn, org.nr, konto og Vipps — alt i UI-et.

## Teknisk

- Alle kronebeløp lagres som **heltall øre** (ingen flyttalls-feil), vises med tusenskille og «kr».
- Alle tidspunkt lagres **UTC**, vises i **Europe/Oslo**.
- Hele appen beskyttes av **HTTP Basic Auth** (`APP_PASSWORD`) — uten passord satt er den åpen (kun for lokal utvikling).
- Mørkt, responsivt tema som fungerer like godt på mobil (390 px) som desktop — viktig når du jobber i felten.

## Kom i gang lokalt

```bash
cd larsen-datasupport
bundle install
ruby db.rb seed          # valgfritt: testkunder + testvarer
bundle exec ruby app.rb  # åpne http://localhost:4567
```

Vil du ha pålogging også lokalt:

```bash
export APP_PASSWORD="hemmelig-passord"
export SESSION_SECRET="$(ruby -e "puts Random.bytes(32).unpack1('H*')")"
bundle exec ruby app.rb
```

## Backup

Databasen er én fil: kopier `data/larsen.db` (ev. med `data/larsen.db-wal` hvis appen kjører). Det er hele backupen.

## Deploy til Fly.io (gratis tier)

```bash
curl -L https://fly.io/install.sh | sh
fly auth login
cd larsen-datasupport
fly launch --now                 # bruker fly.toml og Dockerfile
fly volume create larsen_data --region ams --size 1   # persistent SQLite (kun første gang)
fly secrets set APP_PASSWORD="ditt-hemmelige-passord"
fly secrets set SESSION_SECRET="$(ruby -e "puts Random.bytes(32).unpack1('H*')")"
fly deploy
```

`fly.toml` er satt opp med `shared-cpu-1x` + `auto_stop_machines`/`auto_start_machines` = maskinen sover når den ikke brukes (tilnærmet 0 kr i praksis på gratis-kvoten).

> **Merk:** `fly launch --now` spør om du vil lage volum — si ja til å opprette `larsen_data`, eller kjør `fly volume create`-kommandoen over før `fly deploy`.

### Deploy til Render (alternativ)

Opprett en ny **Web Service** som peker på repoet: runtime Docker (`Dockerfile`), og sett miljøvariablene `APP_PASSWORD`, `SESSION_SECRET` og `PORT=10000`. Render setter `PORT` selv — Dockerfilen leser den.

## Struktur

```
app.rb                  # Sinatra-app med alle ruter
db.rb                   # SQLite-tilkobling + migrering + seed (ruby db.rb seed)
schema.sql              # Databaseskjema
config.ru               # Rack-oppstart for Puma
views/                  # ERB-templates (norsk UI)
public/style.css        # Ett samlet stylesheet
fly.toml, Dockerfile    # Deploy til Fly.io gratis
.env.example            # Miljøvariabler som trengs
```

## Passord

`APP_PASSWORD` er alt som skal til for å låse appen. Sett den alltid i produksjon — de delbare varesidene (`/vare/:id`) er bevisst uten pålogging, alt annet krever passordet.
