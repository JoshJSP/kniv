# Mesje Talen — ontwerp stuk 1 (lezen en luisteren)

Vraaggesprek 01-10-2026. Leerprofiel van Josh: hij leert door veel te horen en te lezen wat hij net
begrijpt, over onderwerpen die hem interesseren (games, internet, reizen, series, muziek). Stampen
werkt niet voor hem, taal-apps vond hij saai en onbruikbaar. Hij leert in de bus (oortjes, niet hardop),
2-5 minuten tussendoor en voor het slapen. Hoofdtaal Duits (kent al wat), daarnaast elke taal die hij wil.

Geslaagd als: Josh opent het een week lang uit zichzelf in de bus, en vindt de stukjes niet saai
en niet te moeilijk.

## Stukken (elk met een eigen ontwerp)
1. **Lezen en luisteren** (dit document)
2. Delen naar Kniv (echte teksten → leesstuk) + kaartjes van je eigen woorden
3. Zelf gebruiken (eigen zinnetje typen, taalmodel verbetert) + slaapmodus
4. Gesprekken
5. Schrift (kana/kanji, andere schriften)

De ingebouwde startpakketten uit de eerste versie van het ontwerp vervallen: voor "alle talen"
kunnen die er niet zijn, en niveau A1-stukjes vervullen hun rol.

## Wat Josh ziet
- **Tegel:** brede tegel "Talen" onder het 3×2-raster. In stuk 1 zonder live info.
- **Eerste keer:** kies je talen uit **alle talen** (zoekbalk, lijst op naam in de taal van Kniv).
  De eerste gekozen taal is de hoofdtaal en staat vooraan. Per taal kies je je niveau met een
  korte uitleg in gewone woorden (A1 "bijna niks" … B2 "series met ondertitels volgen").
- **Bovenin:** met één veeg wissel je tussen je talen. Talen toevoegen of verwijderen gaat via een +-knop.
- **Per taal staat erbij wat kan**, als kleine tekens in de lijst:
  - offline: tekst maken en vertalen gaan op de iPhone zelf
  - online: dit gaat via internet (Groq) en telt mee voor de daglimiet
  - stem: de iPhone kan voorlezen (zonder stem: alleen lezen)
- **Nieuw stukje:** onderwerp-chips (Games, Internet, Reizen, Series, Muziek) plus een eigen onderwerp
  typen. Kniv maakt een stukje van 80-150 woorden op jouw niveau, met een titel.
- **Lezen en luisteren:** grote, rustige tekst. Afspeelknop → de iPhone-stem leest voor, het
  gesproken woord licht op. Snelheid 0,75× / 1× instelbaar.
- **Tik op een woord:** een kaartje met de betekenis in het Nederlands, de uitspraak (opnieuw afspelen)
  en, bij Japans/Chinees, de lezing. Knop "Bewaar" → gaat naar Mijn woorden (samen met de zin waarin
  het stond; in stuk 2 worden dat kaartjes).
- **Na het stukje:** drie knoppen, "Te makkelijk", "Precies goed" en "Te moeilijk". Die schuiven het
  niveau een halve stap op of terug. Er zijn geen punten en geen streaks.
- **Geschiedenis:** eerdere stukjes per taal, om terug te lezen of opnieuw te luisteren.

## Hoe het werkt

### Taalmogelijkheden (Logica/TaalVermogen.swift)
Alles wordt op het toestel bepaald, niets staat vast in de code:
- lijst van alle talen: `Locale.LanguageCode.isoLanguageCodes` met een weergavenaam
- tekst maken offline: `SystemLanguageModel.default` ondersteunt de taal (via `Denker`)
- vertalen offline: `LanguageAvailability` (Translation) geeft `.installed`/`.supported` voor taal → nl
- stem: `AVSpeechSynthesisVoice.speechVoices()` bevat de taal

### Tekst maken (Logica/Leesstuk.swift + Denker)
1. Kan het offline, dan maakt `Denker.vraag` met instructies het stukje (niveau, onderwerp, taal, lengte).
2. Anders gaat het naar de nieuwe Edge Function `taal`, die het stukje plus een woordenlijst (woord → betekenis) als JSON teruggeeft.
3. Controle: niet leeg, en `NLLanguageRecognizer` herkent de doeltaal. Klopt dat niet, dan één
   nieuwe poging. Mislukt die ook, dan volgt een nette melding.

### Woord aantikken
- De tekst wordt in woorden geknipt met `NLTokenizer(.word)`, dat ook Japans en Chinees aankan.
- Betekenis: eerst de woordenlijst van het stukje (bij Groq-stukjes). Anders `TranslationSession`
  als die taal → nl kan. Anders een losse Groq-vraag via `taal`, die meetelt voor de limiet.
- Lezing voor ja/zh: `CFStringTokenizer`-transcriptie (hiragana/pinyin).

### Edge Function `taal` (supabase/functions/taal)
Zelfde opzet als `spraak`: ingelogd, gedeelde daglimiet in `ai_gebruik` (50/dag), Groq-sleutel alleen
op de server. Het model staat in een env-variabele `GROQ_TEKSTMODEL`. Er zijn twee soorten vragen: `stukje`
(taal, niveau, onderwerp) en `woord` (taal, woord, zin).

### Opslag
Lokaal met SwiftData: `Taalkeuze` (taal, niveau, volgorde), `Leesstuk` (taal, titel, tekst, onderwerp,
datum, woordenlijst) en `BewaardWoord` (taal, woord, betekenis, zin, datum). In stuk 1 wordt er nog niet gesynct.

### Foutgevallen
- Online-taal zonder internet: "Deze taal heeft internet nodig". Oude stukjes blijven leesbaar.
- Daglimiet bereikt: "Morgen weer nieuwe online stukjes", met een uitleg dat offline talen gewoon doorgaan.
- Geen stem voor de taal: de afspeelknop is verborgen en er komt een uitleg bij de taal.
- Apple Intelligence staat uit: de taal wordt behandeld als online, met een tip om het aan te zetten.

## Testen
- `Logica/` zonder UI: niveau opschuiven (grenzen A1/C1), JSON van `taal` parsen, woorden knippen
  (nl, de, ja) en de keuze offline/online/geen-stem op basis van ingevoerde mogelijkheden. Asserts in `Tests/main.swift` (draait in CI).
- Edge Function: handmatig met curl na de deploy (stukje en woord, limiet en 401).
- Josh test op zijn iPhone: Duits (offline), een online taal (bv. Swahili) en Japans (lezing).

## Niet in stuk 1
Kaartjes/herhalen, delen naar Kniv, zelf zinnen maken, slaapmodus, gesprekken, schrift, sync,
Windows en web.
