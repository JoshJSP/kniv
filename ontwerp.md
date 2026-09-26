# Kniv — ontwerp (vraaggesprek 26-09-2026, nog niet af)

Een Apple-strak zakmes vol kleine tools voor de iPhone, met een Windows-programma ernaast.
Geslaagd als: vrienden het ook willen hebben.

## Platform
- iPhone 15 Pro+ (Apple Intelligence), native app, geïnstalleerd via **SideStore** (gratis Apple-ID, andere apps al actief → zuinig met app-ID's: app + 1 extensie voor widget/Control/Live Activity; delen-vanuit-apps via Opdrachten).
- Build: **privé** GitHub-repo, macOS-runner in GitHub Actions → unsigned .ipa. Releases + SideStore-bron in apart **openbaar** repo `kniv-releases`.
- Vrienden installeren via dezelfde SideStore-bron. Geen iPad, geen Watch.
- Windows: los programma, **echte Windows 11-look** (Mica). Sneltoets **Win+Shift+K** (Spotlight-venster), volledig venster, systeemvak-icoon, alle mesjes. Start níet automatisch.
- Taal volgt het toestel (NL + EN).

## Data & delen
- **Supabase** (gratis): opslag, sync, realtime (wijzigingen < 1 s live).
- Inloggen met **Google**, verplicht bij eerste keer; daarna werkt alles offline en synct later.
- Per ding kiezen: privé / ook op laptop / gedeeld.
- Alleen tekst synct; originele foto's en spraak blijven op de telefoon (cloud = backup van tekst).
- Delen: uitnodigingslink én vriendenlijst. Gedeelde lijst: jij bent de baas, anderen voegen toe/vinken af. Profielbolletje per item.
- Deellinks: webpagina op **Vercel** (kniv.vercel.app), alleen kijken; meedoen = Google-login. Links verlopen vanzelf (30 d / na event). Mooie WhatsApp-preview-kaart. Geen "neem Kniv"-reclame.
- Geen serverpush (kan niet met SideStore gratis): lokale meldingen voor timers/herinneringen, **badge op tegel** bij wijzigingen van anderen.
- **VESPER** mag lezen én schrijven, ook in gedeelde lijstjes.

## Uiterlijk & gevoel
- Startscherm: **vier glazen tegels** (Vastleggen, Timers, Splitten, Kiezen). Volgt iOS licht/donker, accent **zakmesrood**.
- Icoon: gestileerd lemmet. Mes-motief overal subtiel (tegel openen = uitklappen).
- Veel haptiek, geen geluid. Toon: vriendelijk & warm.
- Eerste keer: intro van 3 schermen → Google-login.
- Instellingen minimaal: account/uitloggen, mijn bakjes, haptiek aan/uit.
- Grenzen: geen ingewikkelde instellingen, openen < 1 s, werkt offline, geen tweede VESPER.

## Mesje 1 — Vastleggen (eerst bouwen)
- Tekst, afvinklijstjes, foto's, spraak.
- Snel: Actieknop = ingedrukt houden en inspreken; widget in meerdere formaten; vergrendelscherm/Control Center; delen vanuit apps.
- Spraak: op het toestel, bij twijfel naar Groq/Whisper (via Supabase Edge Function, sleutel niet in de app).
- Typen: slim herkennen (`- ` → lijstje, "9 okt" → datum).
- Foto: tekst eruit (OCR), herkennen wat het is (bon → Splitten), automatisch rechtzetten.
- Ordent zichzelf in bakjes: vaste set (School, Boodschappen, Ideeën, To-do, Persoonlijk) + eigen; bij twijfel vraagt Kniv met één tik.
- Weergave: rijen per bakje (App Store-stijl), volgorde slim per moment (tijd/agenda/locatie).
- Slim zoeken (betekenis + tekst in foto's).
- Afgevinkt: doorstrepen + haptiek, na 2 s weg.
- Slimme herinnering ("morgen oma bellen") op een vrij moment uit de iPhone-agenda.

## Mesje 2 — Timers
- Pomodoro (lemmet dat inklapt; Live Activity met mini-lemmet + tijd; zet Niet storen aan via Opdrachten; weekoverzicht focusminuten).
- Countdown naar datum, losse benoemde timers, gedeelde countdown.

## Mesje 3 — Splitten & omzetten
- Snel delen door (+fooi), bon scannen en per persoon aantikken, doorlopende pot (ook in vreemde valuta, afrekenen met minste betalingen), betaalverzoek als mooie deelpagina met IBAN-QR.
- Omzetten: valuta, eenheden (koken, afstand, gewicht/lengte, data), procenten/korting. Invoer: vrij typen ("3 cups bloem") of camera op prijskaartje.

## Mesje 4 — Kiezen
- Rad van fortuin (veeg om te draaien, physics), dobbelsteen (schudden, meerdere stenen), munt, teams (puur willekeurig).
- Samen stemmen: veegstemmen (Tinder-stijl), klaar als iedereen gestemd heeft.

## Later
- Mesjes Scanner (QR, document → PDF) en Meten (waterpas, AR-liniaal, dB).

## Aanvullingen (ronde 2)
- iOS 26 bij Josh (Liquid Glass + on-device taalmodel). Ondersteunt **iOS 18+** met fallback: nagemaakt glas, sorteren/spraak via Groq.
- Groq via Edge Function met **limiet per gebruiker** (bv. 50 AI-acties/dag).
- SideStore-bron openbaar (iedereen met link). **Mooie installatiepagina** op Vercel (screenshots, "Toevoegen aan SideStore", uitleg).
- Windows: **WinUI 3 (C#)**, installer + automatische updates via GitHub; ook voor vrienden (downloadknop), niet ondertekend → uitleg "Meer info → Toch uitvoeren". Windows-toast bij wijzigingen van anderen (als Kniv open is).
- **Beheerpaneel** (gebruikers, actief per dag, populairste mesje; geen inhoud) als tabblad in het Windows-programma, alleen zichtbaar voor Josh.
- Sync-conflict: **laatste wint**. Sync-status onzichtbaar (bolletje pas na uren falen).
- Locatie ook op achtergrond: meldingen bij supermarkt, BUas, thuis en zelfgekozen plekken — alleen als er iets nieuws is sinds de vorige melding.
- Siri: "Zet melk op Kniv", "Start focus in Kniv".
- Account verwijderen: knop in Instellingen (wist alles). Gedeelde lijst gaat dan over op het langst aanwezige lid.
- Camera-omzetten: foto maken → resultaat (niet live).
- Rad: strak monochroom, winnaar zakmesrood. Dobbelsteen: glas.

## Aanvullingen (ronde 3)
- Testen: Josh test op zijn telefoon. **Schudden = fout melden** (GitHub-issue), alleen voor Josh' account, niet in het dobbelmesje.
- Versies heten naar **mestypes** (Kniv Opinel, Santoku…). Na update eenmalig een "Wat is nieuw"-scherm.
- Toegankelijkheid **volledig** (VoiceOver, Dynamic Type, minder beweging → fades).
- Control Center/vergrendelscherm: keuze tekst/foto/spraak; actieve lijst mag zichtbaar zijn zonder ontgrendelen.
- Face ID-slot **per bakje** (niet op vergrendelscherm), geen E2E-versleuteling.
- Mesjes koppelen via **suggestie-knopje**: notitie→timer, lijstje→stemming/teams/rad, bon→splitten.
- Windows-snelvenster: balk + recente notities; screenshot plakken (gaat **volledig** gecomprimeerd de cloud in), bestand slepen, link plakken.
- Telefoonfoto-preview in cloud: leesbaar (~150 KB). Opslag bijna vol → oudste previews verkleinen.
- Tegel → mesje: **lemmet klapt eruit**; terug = veeg omlaag of vanaf links. Tegels vast, live info alleen als er iets is. Met 6 mesjes: 3x2-raster.
- Tempo: zo snel mogelijk, zo goed mogelijk.

## Aanpak
- Mesje voor mesje, meteen echt bouwen (geen mockup). Accounts GitHub, Supabase en Google Cloud zijn aanwezig.
- Start: **Vastleggen lokaal eerst** (zonder cloud) op de telefoon; login/sync daarna.
