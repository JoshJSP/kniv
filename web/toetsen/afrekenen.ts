// Afrekenen op de deelpagina moet hetzelfde geven als de app (Tests/main.swift). Draai: npx tsx toetsen/afrekenen.ts
import { afrekenen } from "../app/lib";

function check(ok: boolean, wat: string) {
  if (!ok) { console.error("FOUT: " + wat); process.exit(1); }
}
const tekst = (b: { van: string; naar: string; bedrag: number }[]) => b.map((x) => `${x.van}>${x.naar}:${x.bedrag}`).join(" ");

// zelfde geval als in de Swift-checks: C→A 40, B→A 10
const abc = ["A", "B", "C"];
check(tekst(afrekenen([{ betaaldDoor: "A", bedrag: 90, voor: abc }, { betaaldDoor: "B", bedrag: 30, voor: abc }])) === "C>A:40 B>A:10", "minste betalingen");
check(afrekenen([]).length === 0, "geen uitgaven");
check(afrekenen([{ betaaldDoor: "A", bedrag: 30, voor: ["A"] }]).length === 0, "alleen voor jezelf betaald");
check(afrekenen([{ betaaldDoor: "A", bedrag: 50, voor: [] }]).length === 0, "uitgave zonder mensen telt niet");
check(tekst(afrekenen([{ betaaldDoor: "A", bedrag: 10, voor: abc }])) === "B>A:3.33 C>A:3.33", "afronden op centen");
console.log("afrekenen ok");
