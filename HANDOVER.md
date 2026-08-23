# Larsen Datasupport — HANDOVER / ØKTEDELERE
*Sist oppdatert: 2026-08-23 ~10:05*

> Les `CONTEXT.md` først — det er den evige tråden. Dette er kort handover
> for å ta opp tråden på en annen maskin.

---

## 1. Status nå

- **Alltid arbeid er committet** på `main` som **0794af7** (5 commits foran `origin/main`).
- **Lokal server** kjører på `0.0.0.0:4567` (admin-passord `lol`) — dette MASKINER,
  ikke på versjonsstyrt.
- Alt verifisert i denne økten:
  - OCR-import kontakter (bilde → tesseract `nor+eng` → preview → commit)
  - Dashboard «Neste grep»-suggestions (5 stk)
  - Auto-sync: kunde → kontakt på opprett/oppdater
  - Alle hoved-ruter 200.

## 2. GIT-PUSH STATUS (VIKTIG)

**Problem:** Det lagrede GitHub Personal Access Token (`.git-credentials`)
er **utløpt/revokert** — GitHub API svarar `401 Bad credentials`.
Derfor kunne lokale commits IKKE pushes.

Lokalt ligger **5 commits** klar som venter på push:
```
5a0697d Ikke versjonsstyr .bundle
643a964 Første versjon av appen
e5dfc2f Legg til CONTEXT.md
4e1983d Verifisert hele løypen (alle features) + seed
0794af7 OCR-import + dashboard-suggestions + auto-sync  ← HEAD
```
`origin/main` ligger på `d1944da` (bare byggeprompt + README).

### Hvor wagner deg til å push når du har et fersk token:
```bash
# 1. Opprett ny PAT på GitHub: Settings → Developer settings → Personal access tokens (fine-grained/classic)
#    Gi lese + skriv på repo `trollieske/larsen-datasupport` (repo scope).
# 2. Erstat innholdet av ~/.git-credentials med:
#    https://TOKEN@github.com
# 3. Push:
git push origin main
```
Alt er committet; enkel push klarer det. Når pushet, sjekk `git status` → rent.

## 3. TAKIN-COLLATERA (hvis du møter på nytt på et annent sted)

```bash
git clone https://github.com/trollieske/larsen-datasupport.git
cd larsen-datasupport
# Ruby 3.4 + bundler:
export GEM_HOME=$(gem env user_gemhome); export PATH="$GEM_HOME/bin:$PATH"
bundle config set --local path vendor/bundle
bundle install
# Seed (valgfritt) + start:
ruby db.rb seed
APP_PASSWORD="lol" nohup bundle exec puma -b tcp://0.0.0.0:4567 > /tmp/larsen.log 2>&1 &
curl http://127.0.0.1:4567/health
```
Startside: `http://localhost:4567`, brukernavn vilkårlig + passord `lol`.

## 4. NESTE STEG (fra CONTEXT.md §6)
1. Webshop + prisinlogging (Google sign-in + magic-lenke) — trenger SMTP oppsett.
2. Faktura → CRM-knapp.
3. Utsendelse/log-mailmerge (er ferdig, verifisert).
4. Deploy: `cloudflared tunnel --url http://localhost:4567` eller Fly.io.

## 5. OPPGAVER UTENFOR PROSJEKT
- 🔒 **Lid-close → lock**: bruker MÅ runn:
  `sudo install -o root -g root -m 0644 /tmp/10-lid-close-ignore.conf /etc/systemd/logind.conf.d/10-lid-close-ignore.conf && sudo systemctl restart systemd-logind`
  (full: `~/pi-conversations/2026-08-22-lid-lock.md`)