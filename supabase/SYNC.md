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
| `soort` | `notitie` (later: `timer`, `pot`, `uitgave`, `stemming`) |
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

## Ophalen
`select * from records where gewijzigd > <laatst opgehaald> order by gewijzigd` — RLS geeft alleen eigen records en die van groepen waar je lid van bent. Realtime: postgres_changes op `public.records`.

## Delen
- Groep maken: insert in `groepen` (`eigenaar = auth.uid()`, `soort`, `titel`), `deel_token` komt terug.
- Uitnodigen: `https://kniv.vercel.app/j/<deel_token>` → opent `kniv://join/<deel_token>` → rpc `word_lid(token)`.
- Alleen kijken (zonder account): `https://kniv.vercel.app/g/<deel_token>` → rpc `deelpagina(token)` (anon mag die aanroepen).
- Links verlopen vanzelf (`groepen.verloopt`, standaard 30 dagen).
- Account verwijderen: rpc `verwijder_mij()`; gedeelde groepen gaan over op het langst aanwezige lid.

## Profielen
`profielen(id, naam, avatar)` wordt gevuld vanuit Google bij de eerste login; iedereen die ingelogd is mag ze lezen.
