// Gangpad op de site sorteert hetzelfde als op de iPhone: dezelfde gevallen als Tests/main.swift.
// Draaien: npx tsx toetsen/gangpad.ts (doet de check-web workflow ook).
import { route, van } from "../app/gangpad";
import { NAMEN } from "../app/gangpadWoorden";

const gevallen: [string, string][] = [
  ["Melk", "Zuivel & eieren"], ["2 appels", "Groente & fruit"], ["wc-papier", "Huishouden"], ["pindakaas", "Kaas & beleg"],
  ["volkorenbrood", "Brood"], ["iets raars", "Overig"], ["rucola", "Groente & fruit"], ["sperziebonen", "Groente & fruit"],
  ["koffiebonen", "Ontbijt & koffie"], ["ijsthee", "Drinken"], ["frisdrank", "Drinken"], ["appeltjes", "Groente & fruit"],
  ["tomaatjes", "Groente & fruit"], ["broodje", "Brood"], ["citroenen", "Groente & fruit"], ["chocoladevla", "Zuivel & eieren"],
  ["roomijs", "Diepvries"], ["appelsap", "Drinken"], ["maïs", "Pasta, rijst & blik"], ["diepvriesgroente", "Diepvries"],
  ["chocopasta", "Kaas & beleg"], ["mondwater", "Verzorging"], ["wc papier", "Huishouden"], ["2 pakken melk", "Zuivel & eieren"],
  ["kipfilets", "Vlees & vis"], ["soepkip", "Vlees & vis"], ["pinda's", "Koek, snoep & chips"], ["ijsbergsla", "Groente & fruit"],
  ["crème fraîche", "Zuivel & eieren"], ["lente-ui", "Groente & fruit"], ["snoepjes", "Koek, snoep & chips"],
];

const fouten = gevallen.filter(([item, pad]) => NAMEN[van(item)] !== pad).map(([item, pad]) => `${item}: ${NAMEN[van(item)]}, verwacht ${pad}`);
const looproute = route(["cola", "melk", "appels", "brood"], (x) => x).flatMap(([, lijst]) => lijst).join(",");
if (looproute !== "appels,brood,melk,cola") fouten.push(`looproute: ${looproute}`);

if (fouten.length) {
  console.error("FOUT\n" + fouten.join("\n"));
  process.exit(1);
}
console.log(`Gangpad: alle ${gevallen.length} gevallen goed`);
