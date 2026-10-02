// Boodschappen in looproute-volgorde; dezelfde regels als Kniv/Logica/Gangpad.swift.
// De woordenlijst komt uit gangpadWoorden.ts (gemaakt door scripts/gangpad_poort.py).
import { NAMEN, WOORDEN } from "./gangpadWoorden";

const plat = (s: string) => s.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().normalize("NFC");
const PLATTE = WOORDEN.map((r) => r.map(plat));
const UITGANGEN = ["tjes", "etjes", "jes", "tje", "je", "en", "s", "'s"];

function vormen(w: string): string[] {
  return [w, ...UITGANGEN.filter((u) => w.endsWith(u) && w.length - u.length >= 3).map((u) => w.slice(0, -u.length))];
}

export function van(item: string): number {
  const klein = plat(item);
  const tokens = klein.split(/[^\p{L}'-]+/u).filter(Boolean);
  if (tokens.some((t) => t.startsWith("diepvries"))) return NAMEN.indexOf("Diepvries");
  const alle = new Set(tokens.flatMap(vormen));
  let beste = NAMEN.length - 1, lengte = 0;
  PLATTE.forEach((lijst, pad) => {
    for (const w of lijst) {
      const raak = w.includes(" ")
        ? klein.includes(w)
        : alle.has(w) || [...alle].some((v) => v.endsWith(w) && v.length - w.length >= (w.length >= 4 ? 1 : 3));
      if (raak && w.length > lengte) { beste = pad; lengte = w.length; }
    }
  });
  return beste;
}

/** Groepen in looproute-volgorde; binnen een gangpad blijft de volgorde zoals hij was. */
export function route<T>(items: T[], tekst: (t: T) => string): [string, T[]][] {
  const groepen = new Map<number, T[]>();
  for (const it of items) {
    const k = van(tekst(it));
    groepen.set(k, [...(groepen.get(k) ?? []), it]);
  }
  return [...groepen.keys()].sort((a, b) => a - b).map((k) => [NAMEN[k], groepen.get(k)!]);
}
