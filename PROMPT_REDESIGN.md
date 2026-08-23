# Redesign-prompt: Larsen Datasupport

Kjør fra rota av repoet. Du er staff product designer + senior frontend-utvikler. Gjør en komplett visuell overhaling av eksisterende Sinatra/ERB/CSS-app.

## Absolutte rammer
- Funksjonene finnes: timer, faktura, lager og innstillinger.
- Ikke endre routes, database, form actions, HTMX-attributter eller forretningslogikk.
- Refaktorer kun `public/style.css`, `views/*.erb` og nødvendig minimal vanilla-JS for tema.
- Behold ren CSS/ERB: ingen React, Tailwind, npm, build-steg, ikonfont eller emoji.
- Mobil-first; test 390px, 768px og desktop.

## Mål
Dette skal se ut som et modent, dyrt B2B-SaaS-produkt, ikke et dashboard-template eller et hobbyprosjekt. Kombiner Basecamp-rolig informasjonsarkitektur, Monday.coms ryddige hierarki/statusfarger, Apple-presisjon og OpenRouter-lignende gjennomtenkt lys/mørk-modus.

Fjern alle dagens problemer: emoji-ikoner, flat mørkeblå bakgrunn, kort uten dybde/kontrast, like viktige primær- og sekundærknapper og manglende tema-toggle.

## Designsystem
Bygg om CSS rundt kun tokens. Ikke hardkod farger i komponenter.

```css
:root {
  color-scheme: light;
  --bg-primary:#f7f7f8; --bg-secondary:#fff; --bg-elevated:#fff; --bg-subtle:#f1f2f5;
  --text-primary:#1d1d1f; --text-secondary:#65656d; --text-tertiary:#898990;
  --accent:#5c5cff; --accent-hover:#4b4be8; --accent-soft:rgba(92,92,255,.11);
  --success:#00a866; --success-soft:rgba(0,200,117,.12);
  --warning:#c97800; --warning-soft:rgba(253,171,61,.16);
  --danger:#d53a53; --danger-soft:rgba(226,68,92,.12);
  --border:#e5e5ea; --border-strong:#d4d4da;
  --shadow-sm:0 1px 2px rgba(22,22,26,.05),0 1px 3px rgba(22,22,26,.04);
  --shadow-md:0 8px 24px rgba(22,22,26,.08),0 2px 6px rgba(22,22,26,.04);
  --radius-sm:10px; --radius-md:14px; --radius-lg:20px; --radius-pill:999px;
}
html[data-theme="dark"] {
  color-scheme: dark;
  --bg-primary:#18181a; --bg-secondary:#1f1f22; --bg-elevated:#27272b; --bg-subtle:#303035;
  --text-primary:#f5f5f7; --text-secondary:#b1b1ba; --text-tertiary:#85858e;
  --accent:#8181ff; --accent-hover:#9797ff; --accent-soft:rgba(129,129,255,.16);
  --success:#25c987; --success-soft:rgba(37,201,135,.14);
  --warning:#ffb84f; --warning-soft:rgba(255,184,79,.16);
  --danger:#ff6d83; --danger-soft:rgba(255,109,131,.14);
  --border:#35353a; --border-strong:#46464e;
  --shadow-sm:0 1px 2px rgba(0,0,0,.28); --shadow-md:0 12px 32px rgba(0,0,0,.28),0 2px 8px rgba(0,0,0,.18);
}
```

Bruk systemfont: `-apple-system, BlinkMacSystemFont, "SF Pro Display", "Inter", "Segoe UI", sans-serif`. Implementer skala: xs .75rem, sm .875rem, base 1rem, lg 1.125rem, xl 1.5rem, 2xl 2rem. Kronebeløp/timer/datoer skal bruke `font-variant-numeric: tabular-nums`.

## Tema
Sett `data-theme="light|dark"` på `<html>`. Legg inn en elegant ikonknapp i header med sol/måne-SVG. Ved første besøk velg `prefers-color-scheme`; etter manuelt valg lagre `larsen-theme` i localStorage. Gjør det med minimal vanilla-JS. Begge temaene skal være bevisst designet; mørk modus er varm, nøytral nesten-svart, aldri gaming-blå.

## Ikoner
Erstatt ALLE emoji med inline SVG-er i Lucide outline-stil: `viewBox="0 0 24 24"`, `fill="none"`, `stroke="currentColor"`, `stroke-width="1.8"`, runde linjeender. Mapping: appmerke=wrench eller LD-monogram; Oversikt=layout-dashboard; Timer=timer; Faktura=receipt-text/file-text; Lager=package; Mer=menu; Start timer=play; Legg til vare=plus; Innstillinger=settings-2; tema=sun/moon. Ingen CDN eller icon-font.

## Navigasjon
Lag raffinert header med diskret bunnborder, appmerke/tekst til venstre og tema-toggle til høyre. Gjør mobil bunnnavigasjon native-lignende: fem like brede tabber med SVG over 11–12px label; aktiv farge=`--accent` med subtil indikator; inaktive=`--text-tertiary`; semi-transparent bakgrunn, `backdrop-filter: blur(20px) saturate(150%)`, fallback, top-border og `padding-bottom: env(safe-area-inset-bottom)`. Sikre at main alltid har nok bunnpadding.

## Komponenter
Primærknapp: accent, hvit tekst, 44px minimum touch-høyde, 10–12px radius, svak skygge, hover maks 1px løft, active `scale(.975)`. Sekundærknapp: transparent/elevated, 1px border, normal tekstfarge. Ha synlig fokus-ring og 44×44px på ikonkontroller.

Kort: 14–20px radius, `--bg-elevated`, subtil border/skygge, generøs whitespace. Dashboard-statkort får 40px ikonbadge med `--accent-soft`, liten letter-spaced label, stort tabulært beløp og én kontekstlinje. Fjern dekorative progressbarer uten reell verdi. Statusfarge brukes kun semantisk.

Inputs: label over felt, 44–48px høyde, god kontrast, rolig bakgrunn, border og tydelig focus-ring. Aktiv timer får diskret oransje statusdot og rolig elapsed time.

## Per skjerm
- Oversikt: Start timer er soleklar CTA. Legg til vare sekundær. Tall er skannbare.
- Timer: live-timer som førsteprioritet; manuell registrering klart sekundær.
- Faktura: subtotal, MVA og total er svært tydelige; ryddige rader og små statusbadges.
- Lager: ryddig desktop-liste og mobilvennlige kort; pris, fortjeneste og lagerstatus skiller seg semantisk.
- Innstillinger: grupper i Firma, Faktura og Utseende; ett godt seksjonskort per gruppe, ikke et kort per input.

## Kvalitetskrav
WCAG AA-kontrast (4.5:1 for normal tekst) i begge tema. Ikke horisontal mobilscroll. Respekter `prefers-reduced-motion`. Test lange kunde-/firmanavn. Behold alle eksisterende funksjoner.

## Fullfør
1. Les eksisterende kode før endring.
2. Gjør komplett token-basert CSS-refaktorering og nødvendige ERB-oppdateringer.
3. Kjør `ruby app.rb`, fiks feil og test Oversikt, Timer, Faktura, Lager, Innstillinger i begge tema.
4. Kontroller med `git diff` at kun presentasjon/tema/tilgjengelighet er endret.
5. Commit og push:
```bash
git add -A
git commit -m "Redesign: profesjonelt designsystem med SVG-ikoner og lys/mørk modus"
git push
```

Ikke stopp når det bare er «bedre». Lever en komplett og konsekvent v4.0-produktopplevelse som føles finpusset av et profesjonelt designteam.