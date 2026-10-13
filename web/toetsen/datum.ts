// Countdown op de deelpagina telt kalenderdagen in Nederlandse tijd, net als de app. Draai: npx tsx toetsen/datum.ts
import { dagenTot, zelfdeId, geldFormaat } from "../app/lib";

function check(ok: boolean, wat: string) {
  if (!ok) { console.error("FOUT: " + wat); process.exit(1); }
}
const nu = new Date("2026-10-14T07:00:00Z");
check(dagenTot(new Date("2026-10-14T16:00:00Z"), nu) === 0, "later vandaag = vandaag");
check(dagenTot(new Date("2026-10-15T06:00:00Z"), nu) === 1, "morgen");
check(dagenTot(new Date("2026-10-14T22:30:00Z"), nu) === 1, "na middernacht NL = morgen");
check(dagenTot(new Date("2026-10-26T10:00:00Z"), nu) === 12, "over de zomertijd heen");
check(dagenTot(new Date("2026-10-01T10:00:00Z"), nu) === 0, "voorbij = 0");
check(zelfdeId("E621E1F8-C36C-495A-93FC-0C247A3E6E5F", "e621e1f8-c36c-495a-93fc-0c247a3e6e5f"), "id hoofdletters");
check(geldFormaat("€").format(1).includes("€"), "rare valuta valt terug op euro");
console.log("datum ok");
