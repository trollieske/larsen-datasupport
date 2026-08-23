# UX-iterasjon: Larsen Datasupport

Les kodebasen først. Behold Sinatra, ERB, HTMX, CSS, SVG-ikoner, tema og eksisterende funksjonalitet. Ikke bruk React, Tailwind, npm eller ny database. Mobil først.

## Mål
Gjør appen til et raskt personlig business cockpit: mindre skjema, færre trykk og informasjon kun når den er relevant. Timeren er ikke en permanent hovedflate.

## Timer
Når ingen timer går: erstatt stor form med en kompakt 44–48px «Start timer»-handling. Den åpner bottom sheet/dialog med Kunde, Beskrivelse og Start timer. Avanserte/manuelle felt ligger under «Flere valg». Manuell registrering er sekundær handling.

Når timer går: vis slank persistent bar under header på Oversikt, Timer, Faktura og Lager: statusdot, kunde, beskrivelse, tabulær tid og Stopp. Maks to rader mobil. Trykk åpner detaljer. Ikke parallelle timere. Gi toast etter stopp.

Timer-siden: quick-action/aktiv bar, «I dag» med timer/beløp/antall, kompakte nylige rader med kunde, beskrivelse, varighet, beløp og «Gjenta» som forhåndsvelger kunde/beskrivelse.

## Oversikt
Rekkefølge: aktiv timer når relevant; maks to handlinger (Start timer primær, Registrer salg/Legg til vare sekundær); «Trenger oppfølging» kun med ekte data (ufakturert/lavt lager); tre kompakte KPI-er (Denne måneden, Ufakturert, Lagerverdi); maks fem siste aktiviteter. Bruk gode tomtilstander, ikke tomme cards/progressbarer.

## Faktura
Kundekort: navn, ufakturert total, antall timer/varer og «Klargjør faktura». Legg timerader og MVA-grunnlag bak «Vis grunnlag». Før markering: referanse, dato, subtotal, MVA, total. Valgfritt filter Klar nå/Fakturert/Alle. God tomtilstand.

## Lager
Mobil viser maks to KPI-er direkte. Varekort: status/type, navn, pris/fortjeneste, handlinger; varenummer sekundært. «Selg» primær, «Rediger» sekundær, overflow for kopier/slett. Selg åpner rask sheet med antall=1, pris, valgfri kunde og bekreft. Forutsigbare produktbilder/placeholders og flerbildeteller. Legg til kompakt søk og På lager/Utsolgt/Alle hvis mangler.

## Skjema/kvalitet
Del Legg til vare i Produkt, Pris og Lager. Bruk Kostpris, Salgspris, Fortjeneste per stk og norsk tallformat `5 000 kr`; `font-variant-numeric: tabular-nums`. Ingen card inni card. 44px touchmål, WCAG AA, aria-labels, fokus, reduced motion, safe areas, ingen horisontal scroll. Behold token-systemet; shadows kun på sheets/dialoger.

## Fullfør
Implementer timer først, så Oversikt/Faktura/Lager. Kjør `ruby app.rb`, test lys/mørk på mobil/desktop og flytene start/stopp/manuell/gjenta/fakturering/salg/ny vare/manglende bilde/lenge navn. Sjekk `git diff`. Commit og push:
```bash
git add -A
git commit -m "UX: kompakt timerflyt og raskere operativ arbeidsflate"
git push
```