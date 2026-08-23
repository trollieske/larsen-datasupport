# Larsen Datasupport — KOMPLETT KONTEXT / FREMDRIKT
*Sist oppdatert: 2026-08-23 ~09:50 (OCR-import kontakt fullført)*

> Dette dokumentet er den evige "tråden". Hvis vi starter på nytt, les DETTE først —
> alt av v1, videreutviklingsplanen og tekniske lærdommer står her.

---

## 1. HVA DETTE ER

Superlettvekts Ruby-app (Sinatra + SQLite + ERB + HTMX, ingen npm/build/Rails) for
enmannsbedriften **Larsen Datasupport** (IT-support på timebasis + hardware-salg).
Hele databasen er én fil: `data/larsen.db` (backup = kopier filen).

**Prodvisjon (fra brukeren):** "Omarchy for faktura og timelogg i ett" — alt-i-ett,
superenkel, skalerbar, for nerds OG vanlige folk. Ekte produkt, ikke øvelse.

## 2. STATUS-PANEL

| Modul | Status |
|---|---|
| v1: Timer, faktura, hardware-lager, kunder, innstillinger | ✅ FERDIG + VERIFISERT |
| Deploy-klar: Dockerfile, fly.toml, .env.example, README | ✅ FERDIG |
| Git-repo klar (commit "Første versjon...") | ✅ FERDIG (3 commits totalt) |
| 🔄 Inventory-geniet (kortvegg + foto + HTMX) | 🔄 **PÅGÅR — HALVVEIS (se §5)** |
| Webshop + prisinlogging (Google + magisk lenke) | ⏭ neste |
| Auto-e-post fakturautsending (outbox-mønster) | ⏭ (emails-tabell allerede lagt til!) |
| CRM-som-ikke-er-CRM (Kontakter + OCR-import fra skjermbilde) | ✅ FERDIG + VERIFISERT |
| Dashboard «Neste grep»-suggestions | ✅ FERDIG + VERIFISERT |
| Auto-sync kunde → kontakt | ✅ FERDIG + VERIFISERT |
| Mailmerge/reklame (maler + tags) | ⏭ |

**Meny-navigasjon / ruter:**
`/` oversikt · `/timer` · `/faktura` (+`/faktura/print?ref=`) · `/hardware` ·
`/kunder` · `/innstillinger` · `/#/vare/:id` offentlig delbar side (uten auth).
Autentisering: HTTP Basic Auth, `APP_PASSWORD` env; `/vare/*` og `/upload/*` alltid offentlig.

## 3. TEKNISK KORETAK (viktige lærdommer!)

- **Ruby 3.4** lokalt (3.3-spes i Docker) — kjører med lokal gem-bane:
  ```bash
  export GEM_HOME=$(gem env user_gemhome)
  export PATH="$GEM_HOME/bin:$PATH"
  cd ~/Projects/larsen-datasupport
  bundle config set --local path vendor/bundle   # ⚠ .bundle/ MÅ IKKE committes (i .gitignore nå)
  bundle install
  ```
- **Ruby 3.4 krever `gem "erb"` eksplisitt** i Gemfile (ellers LoadError) ✅ fikset.
- **rack-session** krever `SESSION_SECRET` ≥ 64 tegn — default er fylt 74 tegner ✅.
- **Puma-binding:** `bundle exec puma -b tcp://0.0.0.0:4567` (sinatra `-o 0.0.0.0` virket ikke!)
- **Kjør lokalt:** `ruby db.rb seed` (valgfritt) → `bundle exec ruby app.rb -o 0.0.0.0 -p 4567`
- **Restart:** `fuser -k 4567/tcp; sleep 1; ...` (bruk aldri `pkill -f app.rb` — dreper egen shell)
- Penger: INTEGER ØRE. Datoer: UTC i DB, Europe/Oslo i visning.
- Testserver i gang NÅ: `0.0.0.0:4567` med `APP_PASSWORD="lol"`.
- Windows-pc nås via **SSH-tunnel:** `ssh -L 4567:localhost:4567 ck2k@192.168.0.152` → åpne `http://localhost:4567` (brukernavn: vilkårlig, passord `lol`). Nettleser-proxy blokkerer direkte-LAN til port 4567; SSH fungerer. Status: ✅ VELYKKET — brukeren fikk det til!
- **MOBIL-TILGANG (2026-08-23):** Cloudflare quick tunnels (`cloudflared tunnel --url ...`) ER ØDELAGT — edge returnerer "Host not permitted" (403 med cf-ray) fordi hostname→connector-mappingen aldri registerer seg (testet 2026.8.2 OG 2025.2.0, quic og http2, også utenfra via r.jina.ai). Ikke kast tid på det igjen!
  **Bruk Tailscale i stedet (allerede pålogget på denne maskinen, konto tomeriklarsen1@gmail.com):**
  ```bash
  # På mobilen: installér Tailscale-appen, logg inn med samme Google-konto, så åpne:
  #   http://100.84.216.12:4567   (eller http://omathinkpad:4567)
  # Innlogging i appen: brukernavn hva som helst + passord lol
  # WireGuard-kryptert mellom mobil og PC uansett — HTTP i app-laget er ok.
  # Mulig oppgradering til HTTPS (krever ETT klikk fra eier):
  #   åpne https://login.tailscale.com/f/serve?node=nv6Wd8kxCw11CNTRL → aktiver Serve
  #   deretter: tailscale serve --bg http://127.0.0.1:4567  → https://omathinkpad.tailbdf206.ts.net
  ```

## 4. HVA SOM ER FERDIG OG KONTRAKTERT

**Timer:** start/stopp én knapp, live-nedtelling (HTMX poll 10s), manuell registrering
(minutter ELLER start/slutt), filter dag/uke/måned/alt + per kunde, sum kroner.
**Faktura:** "Klar for fakturering" grupperer per kunde (timer + salg = subtotal,
+25% mva = total), knapp "Merk som fakturert" → lager `F-ÅÅÅÅ-NNN` + print-view
(`window.print()`, ingen PDF-gem). Siste fakturaer-liste.
**Hardware:** CRUD varer, salg trekker lager, fortjeneste/vare, lagerverdi.
**Kunder:** CRUD, pr. kunde timepris-avvik (øre).
**Innstillinger:** standardpris (850kr/t), mva (25%), firmanavn, org.nr, konto, Vipps, kontakt-e-post, **public_base_url** (ny).
**Dashboard:** månedens timer + beløp, ufakturert "penger som venter", siste aktivitet.
**Seed:** 3 testkunder + 4 varer (Dell-skjerm osv).

## 5. ✅ PÅGÅENDE: "INVENTORY-GENIET" (brukerens store ønske)

**Visjon (fra brukeren):** "Få inn inventory på en helt banebrytende genial måte
hva gjelder enkelhet og brukervennlighet."

**Designet (mitt forslag, godtatt som retning):**
- Kortvegg i stedet for tabell: hver vare = kort med bilde, navn, kategori, priser.
- "Solgt" i 3 trykk: kvantum → pris (forhåndsutfylt) → «Solgt!».
- "Kopier til Finn/Facebook" — ferdigformatert salgstekst i clipboard, + delbar side.
- **Foto:** enkel bildeopplasting, tjent via `/upload/`, offentlig (for webshop senere).
- HTMX overalt — alt oppdateres live uten side-refresh.

### GJØRT SÅ LANGT (i kode, IKKE verifisert enda):
- [x] `db.rb`: `UPLOADS_DIR`, migrering + `photo`/`tags` kolonner, `public_base_url` default.
- [x] `schema.sql`: `photo` på hardware_items + **ny `emails`-tabell** (outbox, allerede der!).
- [x] `app.rb`: helpers `save_photo/delete_photo/stock_value/potential_profit/realized_profit/hardware_stats/render_cards!/hx?/public_path?/queue_email`, ruter for kort (HTMX), foto-opplasting på ny/rediger, `/upload/:file`-rute, public_path utvidet, innstillinger-route for public_base_url.
- [x] `views/settings.erb`: public_base_url felt.

### VERIFISERT (test 2026-08-23 – inventory-geniet / mobil):
- [x] FIX: `render_cards!` manglet `@customers`/`@base_url` → HTMX-kortvegg-fragment kraset NoMethodError. Nå satt opp – fragment returnerer kort med kundevalg + kopier-lenk.
- [x] Legg-til-vare (HTMX), Selg-flyt (lager-trekk + realisert oppdatert), Slett-fly.
- [x] Magisk-lenke (dev) → 302 → web_user opprettet → pris vises på /vare/:id.
- [x] OCRimport-text, /epost + flush, alle admin-ruter 200.

### MANGELR (neste steg — gjør nå):
- [ ] `views/_cards.erb` — kortpartialet (HTMX-mål). Innhold per kort:
      foto (ph-emoji fallback), navn, kategori-tag, kost→salg, på-lager badge ("2 på lager"),
      "Selg"-knapp (details-popup → antall/pris/kunde → POST `/hardware/:id/sell` hx-post + hx-target),
      "Kopier"-knapp (JS: clipboard `name · category · pris · url vare/:id`),
      rediger + slett (hx-post/hx-delete).
- [ ] `views/_cards_flash.erb` — liten flytende flash-for-HTMX.
- [ ] `views/hardware.erb` — NY omskriving: stat-header (lagerverdi, potensiell fortjeneste,
      realisert), "Legg til vare"-fly (modal/popup med foto-opplasting), enkel "søk/filter"-input
      (hx-get `/hardware/cards` hx-trigger keyup), kortvegg `<div id="cards">` med hx-target.
- [ ] `public/style.css` — kortrutenett, kortstiler, popup, fil-opplastningsfelt, badge-osv.
- [ ] Verifiser: restart, test kortvegg, salg fly, foto, kopier-lenke, HTMX-fragmenter.
- [ ] Commit: "Inventory-geniet: kortvegg med foto, salg og kopier-til-Finn".

### Teknisk for HC-kortsamtalen (delvis kontrakt klart):
- Kort-hyperlink til `/vare/:id` (offentlig) — allerede fungerer.
- Foto: POST multipart med `name="photo"`, `save_photo` returnerer filnavn; `send_file` for `/upload/`.
- Fluks: HTMX-respons på `/hardware`-POST = `render_cards!` (partial), så kortveggen oppdateres umiddelbart.

## 6. VIDEREPLAN (brukerens store visjon, i rekkefølge)

1. **Inventry-geniet** (pågår, §5)
2. **Webshop + prisinlogging:** offentlig butikk-tema på `/vare/:id` + oversikt,
   "Logg inn for pris" — **Google sign-in** (OAuth) + **magisk-lenke-innlogging** (epost-lenke,
   ingen passord — "for vanlige folk"). Pris vises kun for innloggede.
3. **Auto-e-post:** når du fakturerer → faktura sendes automatisk. **Outbox-mønster**
   (emails-tabellen, allerede lagt til) — e-postkø i DB, prosesseres ved oppstart/timer,
   ingen ekstern jobb-infrastruktur. Skalerbart: bytt til Postgres uten å røre logikk.
4. **CRM-som-ikke-er-CRM:** "Kontakter" — alt i én liste, søk, tags, tidslinje per kontakt
   (timer + salg + fakturaer + e-poster). Ingen kanban-bloat, bare det man trenger.
5. **Mailmerge / reklame:** malbasert masse-e-post til taggede kontakter ({{navn}}, {{pris}}),
   utsending via outbox. Design: genialt, minimalistisk, vakkert.

**Skalerbarhetsprinsipp (brukeren:** "Tenk ut selv hva som er banebrytende, skalerbart,
superenkelt"): tynt servicelag + data-modell som tåler bytte til Postgres; ingen ekstern
avhengighet for e-post (outbox); alt offline-first (én fil); deploy gratis Fly.io som sover.

## 7. LØSNINGER / BESLUTNINGER VI HAR TATT

- Omarchy-style: opinionated, konfigurasjon i UI (innstillinger), INTET CLI-junk.
- Basic Auth nå; senere riktig innlogging (magisk lenke + Google) for webshop-kunder.
- e-post: aldri direkte SMTP i rute — alltid via outbox (emails-tabell).
- Priser i øre ↔ visning kroner. Datoer UTC ↔ Oslo.
- Norsk UI, engelske kodekommentarer.

## 8. OPPGAVER SOM HENGER IGJEN (utenfor prosjektet)

- 🔒 **Lid-close → lock (lenge ventende):** /tmp/10-lid-close-ignore.conf inneholder
  HandleLidSwitch=lock kommandoer. Brukeren MÅ kjøre:
  `sudo install -o root -g root -m 0644 /tmp/10-lid-close-ignore.conf /etc/systemd/logind.conf.d/10-lid-close-ignore.conf && sudo systemctl restart systemd-logind`
  Revert: `sudo rm /etc/systemd/logind.conf.d/10-lid-close-ignore.conf && sudo systemctl restart systemd-logind`
  (full kontekst: ~/pi-conversations/2026-08-22-lid-lock.md)

## 9. DRIFT-COMMANDS (snarvei)

```bash
export GEM_HOME=$(gem env user_gemhome); export PATH="$GEM_HOME/bin:$PATH"
cd ~/Projects/larsen-datasupport
fuser -k 4567/tcp 2>/dev/null; sleep 1
APP_PASSWORD="lol" nohup bundle exec puma -b tcp://0.0.0.0:4567 > /tmp/larsen.log 2>&1 &
sleep 4; curl -s http://127.0.0.1:4567/health
# Windows-tilgang: ssh -L 4567:localhost:4567 ck2k@192.168.0.152  → http://localhost:4567
```
## 10. ✓ Fullført i denne økten (2026-08-23 ~01:20)

- **App ferdig & verifisert**: admin-auth (Basic), HTMX-kortvegg med foto+selg, offentlig delbar vareside `/vare/:id` med prislåsing, magisk-lenke-innlogging + Google OAuth (gracefull nedfall), CRM "kontakter" + tidslinje (per kontakt: timer/salg/faktura/epost), e-post-outbox + SMTP-flush, mailmerge `{{navn}}`, automatisk faktura-e-post i kø.
- **Sådd**: 3 kunder + 5 kontakter + 4 varer (med foto) — alle i `data/larsen.db`.
- **Windows-tilgang** fungerer via SSH-tunnel: `ssh -L 4567:localhost:4567 ck2k@192.168.0.152` → `http://localhost:4567` (passord `lol`).
- **Deploy:** `cloudflared tunnel --url http://localhost:4567` (trycloudflare.com, ingen konto) — eller Fly.io med `fly launch` + `fly secrets set APP_PASSWORD ...` (krever brukerens login).
- **Neste steg:** webshop med Google-innlogging + magisk lenke trenger SMTP satt opp; faktura-til-CRM-knapp.

### ✦ Tillegg 2026-08-23 ~09:35 (OCR-import + dashboard)
- **OCR-import fra skjermbilde (i Kontakter):** dra/slipp, Ctrl+V-lim, eller opplast → tesseract `nor+eng` → `extract_contacts` (epost/telefon/navn) → preview med redigering → commit. Rute-ordning viktig: `/kontakter/import` osv. MÅ stå FØR `/kontakter/:id` (ellers `:id` fanger dem).
- **Tekn. lærd:** ikke bruk `Open3` (fantes ikke) — bruk `Shellwords.join([...])` + backticks. `TESSDATA_PREFIX` til `data/tessdata/`; la inn `eng.traineddata` (kopiert fra system) i tillegg til `nor`.
- **Dashboard «Neste grep»:** 5 suggestion-ka.
- **Auto-sync:** kunde opprettet/oppdatert → kontakt (match på e-post, unik-avderburg).
- Verifisert: alle hoved-ruter 200; bilder-Niest + commit + text-OCR virker ende-til-ende; DB-rydset for testimport.
