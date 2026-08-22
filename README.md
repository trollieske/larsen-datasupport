# Larsen Datasupport

Internt verktøy for timeregistrering, fakturaberegning og hardware-lager for Larsen Datasupport.

## Hva er dette?
Et ekstremt lettvekts Ruby/Sinatra + SQLite-verktøy, designet for å bygges direkte i terminalen med Pi CLI + DeepSeek. Ingen Rails, ingen npm, ingen build-steg — bare `bundle install` og kjør.

## Kom i gang
Se [PROMPT.md](./PROMPT.md) — dette er den fullstendige, geniale byggeprompten som brukes med Pi (`pi.dev`) og DeepSeek for å generere hele appen (app.rb, views, CSS, Dockerfile, fly.toml osv.) direkte i terminalen.

### Slik bruker du den
```bash
curl -fsSL https://pi.dev/install.sh | sh
cd larsen-datasupport
pi
# Lim inn innholdet fra PROMPT.md når Pi spør hva du vil bygge
```

## Funksjonalitet (v1)
- Start/stopp-timer per kunde med automatisk minuttberegning
- Manuell timeregistrering
- Fakturaklar-oversikt med mva-beregning (25%) og utskriftsvennlig faktura
- Hardware-lager med kostpris/salgspris og fortjeneste-oversikt
- Offentlig delbar "interessert i denne varen"-lenke for Finn.no/Facebook-salg
- Beskyttet med enkel HTTP Basic Auth (`APP_PASSWORD`), null kostnad å hoste på Fly.io eller Render

## Stack
Ruby 3.3 · Sinatra · SQLite · HTMX · ren CSS · Puma · Docker · Fly.io (gratis tier)
