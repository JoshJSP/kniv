# Kniv-sync: het contract tussen iPhone, Windows en web

Supabase-project `ykptlgckqppgxirtndch` (Frankfurt), URL `https://ykptlgckqppgxirtndch.supabase.co`.
Publishable key (mag in apps en web): `sb_publishable_5oWWatyeuq3o-w3Qw_R_jA_qo…` (volledig: `SUPABASE_PUBLISHABLE` in `C:\Users\joshk\.kniv\supabase.env`).
De **secret** key komt nooit in een app die anderen krijgen (alleen in het beheerpaneel op Josh' laptop).

Schema: `supabase/schema.sql`. Alles beveiligd met RLS.

## Inloggen
Alleen Google, via Supabase Auth.
- iPhone: `signInWithOAuth(provider: .google, redirectTo: "kniv://auth")`
- Windows: OAuth met PKCE via loopback `http://localhost:53682/auth` (staat in de allow-list)
- Web: `https://kniv.vercel.app/**`

## Records (`public.records`)
| kolom | betekenis |
|---|---|
| `id` uuid | stabiele id van het ding, op elk apparaat hetzelfde |
| `eigenaar` uuid | wie het maakte (`auth.uid()`) |
| `groep` uuid? | gedeelde groep, anders null (= alleen eigen apparaten) |
| `soort` | `notitie`, `timer`, `pot`, `uitgave`, `prik`, `prikstem`, `taal`, `leesstuk`, `woord` |
| `data` jsonb | inhoud, zie hieronder |
| `gewijzigd` timestamptz | tijd van de laatste wijziging, ISO-8601 met fracties, UTC |
| `gewijzigd_door` uuid | wie de laatste wijziging deed (voor het profielbolletje) |
| `verwijderd` bool | zacht verwijderd; andere apparaten verwijderen het dan lokaal |

**Conflicten: laatste wijziging wint** (hoogste `gewijzigd`). Upsert op `id`.
"Privé" (alleen deze telefoon) wordt nooit gesynchroniseerd.

### data voor `soort = notitie`
```json
{
  "tekst": "Boodschappen",
  "fotoTekst": "",
  "bakje": "Boodschappen",          // null = nog niet gesorteerd
  "gemaakt": "2026-09-27T10:00:00.000Z",
  "items": [ { "tekst": "melk", "volgorde": 0, "door": "<uuid of null>" } ]
}
```
Foto's gaan (nog) niet mee; alleen `fotoTekst`.

### data voor `soort = timer` (losse timer of countdown; alleen iPhone)
```json
{ "naam": "Pasta", "isCountdown": false, "duur": 540, "eind": "2026-09-27T10:09:00Z", "rest": null, "doel": null }
```

### data voor `soort = pot` en `soort = uitgave` (potjes; alleen iPhone)
```json
{ "naam": "Barcelona", "valuta": "EUR", "leden": ["Ik", "Sam"], "gemaakt": "…" }
{ "pot": "<uuid van het potje>", "omschrijving": "Pizza", "bedrag": 24.5, "betaaldDoor": "Ik", "voor": ["Ik", "Sam"], "datum": "…" }
```
Uitgaven zijn aparte records, zodat twee mensen tegelijk iets kunnen toevoegen. Een gedeeld potje: potje én uitgaven krijgen dezelfde `groep`.
### data voor `soort = prik` en `soort = prikstem` (datumprikker; alleen iPhone)
```json
{ "naam": "Etentje", "opties": ["2026-10-03T17:00:00Z", "2026-10-04T17:00:00Z"], "gemaakt": "…" }
{ "prik": "<uuid van de prik>", "naam": "Josh", "wie": "<auth uid>", "ja": ["2026-10-03T17:00:00Z"] }
```
### data voor `soort = taal`, `soort = leesstuk` en `soort = woord` (Talen; alleen iPhone)
```json
{ "taal": "es", "stap": 3, "volgorde": 0, "gemaakt": "2026-10-03T10:00:00.000Z" }
{ "taal": "es", "titel": "En el bus", "tekst": "…", "onderwerp": "Reizen", "niveau": "A2", "woorden": { "autobús": "bus" }, "vragen": "{\"vragen\":[…]}", "gemaakt": "…" }
{ "taal": "es", "woord": "autobús", "betekenis": "bus", "zin": "Voy en autobús.", "gemaakt": "…" }
```
Altijd `groep = null` (niet deelbaar). Eén `taal`-record per taalcode; dubbele codes ruimt de iPhone op (nieuwste `gewijzigd` blijft).
`vragen` is de JSON-tekst van de begripsvragen (Oefenen.bewaar), leeg als ze nog niet gemaakt zijn.

Windows haalt alleen `soort=notitie` op en negeert de rest.

## Ophalen
`select * from records where ontvangen >= <laatst opgehaald> order by ontvangen` — `ontvangen` zet de server (trigger) bij elke wijziging, dus offline gemaakte wijzigingen komen ook aan. Een trigger laat een upsert met een oudere `gewijzigd` niets overschrijven (laatste wijziging wint, ook op de server). — RLS geeft alleen eigen records en die van groepen waar je lid van bent. Realtime: postgres_changes op `public.records`.

## Delen
- Groep maken: insert in `groepen` (`eigenaar = auth.uid()`, `soort`, `titel`), `deel_token` komt terug.
- Uitnodigen: `https://kniv.vercel.app/j/<deel_token>` → opent `kniv://join/<deel_token>` → rpc `word_lid(token)`.
- Alleen kijken (zonder account): `https://kniv.vercel.app/g/<deel_token>` → rpc `deelpagina(token)` (anon mag die aanroepen).
- Links verlopen vanzelf (`groepen.verloopt`, standaard 30 dagen).
- Account verwijderen: rpc `verwijder_mij()`; gedeelde groepen gaan over op het langst aanwezige lid.

## Profielen
`profielen(id, naam, avatar)` wordt gevuld vanuit Google bij de eerste login; iedereen die ingelogd is mag ze lezen.
