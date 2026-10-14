import { cache } from "react";

const SUPABASE = "https://ykptlgckqppgxirtndch.supabase.co";
// Publishable key: mag openbaar (RLS beschermt alles; anon mag alleen deelpagina aanroepen).
const KEY = "sb_publishable_5oWWatyeuq3o-w3Qw_R_jA_qo5Tjv_l";

export const SITE = "https://kniv.vercel.app";

export type Item = { tekst: string; volgorde?: number; door?: string | null };
export type KnivRecord = {
  id: string;
  soort: string;
  door: string | null;
  avatar: string | null;
  data: { tekst?: string; items?: Item[]; doel?: string; titel?: string; bakje?: string; [k: string]: unknown };
};
export type Deel = {
  titel: string;
  soort: string;
  verloopt: string | null;
  eigenaar: string | null;
  records: KnivRecord[];
  mensen?: Record<string, { naam: string; avatar: string | null }>;
};

/** Haalt een gedeelde groep op; null = onbekend of verlopen. Een storing gooit een fout (error.tsx), zodat die niet als "verlopen" verschijnt. */
export const haalDeel = cache(async (token: string): Promise<Deel | null> => {
  if (!/^[A-Za-z0-9_-]{1,100}$/.test(token)) return null;
  const res = await fetch(`${SUPABASE}/rest/v1/rpc/deelpagina`, {
    method: "POST",
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify({ token }),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`deelpagina ${res.status}`);
  return (await res.json()) as Deel | null;
});

/** Tijdcapsules blijven dicht tot hun datum. */
export const verzegeld = (r: KnivRecord) => typeof r.data?.verzegeldTot === "string" && Date.parse(r.data.verzegeldTot) > Date.now();

/** Geldformaat; een onbekende valutacode valt terug op euro. */
export function geldFormaat(valuta: unknown): Intl.NumberFormat {
  try {
    return new Intl.NumberFormat("nl-NL", { style: "currency", currency: typeof valuta === "string" ? valuta : "EUR" });
  } catch {
    return new Intl.NumberFormat("nl-NL", { style: "currency", currency: "EUR" });
  }
}

/** Zelfde id, ook als de app hem in hoofdletters opsloeg (Swift UUID) en Postgres kleine letters geeft. */
export const zelfdeId = (a: unknown, b: string) => typeof a === "string" && a.toLowerCase() === b.toLowerCase();

/** Datum van een countdown, als die er is. */
export function doelVan(d: Deel): Date | null {
  for (const r of d.records) {
    const t = r.data?.doel;
    if (typeof t === "string" && !isNaN(Date.parse(t))) return new Date(t);
  }
  return null;
}

/** Kalenderdagen tot de datum in Nederlandse tijd, zoals de app; 0 = vandaag. */
export function dagenTot(doel: Date, nu = new Date()): number {
  const dag = (d: Date) => Date.parse(d.toLocaleDateString("en-CA", { timeZone: "Europe/Amsterdam" }));
  return Math.max(0, Math.round((dag(doel) - dag(nu)) / 86_400_000));
}

/** Korte samenvatting voor previews: "nog 12 dagen" of "5 items". */
export function samenvatting(d: Deel): string {
  const doel = doelVan(d);
  if (d.soort === "countdown" && doel) {
    const n = dagenTot(doel);
    return n === 0 ? "vandaag" : n === 1 ? "nog 1 dag" : `nog ${n} dagen`;
  }
  const potUitgaven = d.records.filter((r) => r.soort === "uitgave");
  if (d.soort === "prik") {
    const opties = ((d.records.find((r) => r.soort === "prik")?.data?.opties as string[] | undefined) ?? []).length;
    const stemmen = d.records.filter((r) => r.soort === "prikstem").length;
    return `${opties} data · ${stemmen} ${stemmen === 1 ? "stem" : "stemmen"}`;
  }
  if (d.soort === "pot") {
    const totaal = potUitgaven.reduce((s, r) => s + (Number(r.data?.bedrag) || 0), 0);
    const valuta = d.records.find((r) => r.soort === "pot")?.data?.valuta;
    return `${potUitgaven.length === 1 ? "1 uitgave" : `${potUitgaven.length} uitgaven`} · ${geldFormaat(valuta).format(totaal)}`;
  }
  const items = d.records.filter((r) => !verzegeld(r)).reduce((n, r) => n + (r.data?.items?.length || (r.data?.tekst ? 1 : 0)), 0);
  return items === 1 ? "1 item" : `${items} items`;
}

export type Uitgave = { omschrijving?: string; bedrag?: number; betaaldDoor?: string; voor?: string[]; datum?: string; pot?: string };

/** Zelfde regels als de app (Kniv/Logica/Rekenen.swift): saldo per persoon, dan zo min mogelijk overboekingen. */
export function afrekenen(uitgaven: Uitgave[]) {
  const saldo: Record<string, number> = {};
  for (const u of uitgaven) {
    const voor = u.voor ?? [];
    if (!voor.length || !u.betaaldDoor || !u.bedrag) continue;
    saldo[u.betaaldDoor] = (saldo[u.betaaldDoor] ?? 0) + u.bedrag;
    for (const p of voor) saldo[p] = (saldo[p] ?? 0) - u.bedrag / voor.length;
  }
  const krijgers = Object.entries(saldo).filter(([, v]) => v > 0.005).sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const betalers = Object.entries(saldo).filter(([, v]) => v < -0.005).map(([k, v]) => [k, -v] as [string, number])
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
  const uit: { van: string; naar: string; bedrag: number }[] = [];
  let i = 0, j = 0;
  while (i < betalers.length && j < krijgers.length) {
    const b = Math.min(betalers[i][1], krijgers[j][1]);
    uit.push({ van: betalers[i][0], naar: krijgers[j][0], bedrag: Math.round(b * 100) / 100 });
    betalers[i][1] -= b;
    krijgers[j][1] -= b;
    if (betalers[i][1] < 0.005) i++;
    if (krijgers[j][1] < 0.005) j++;
  }
  return uit;
}

/** Code van een samen-kiezen-link: vier letters, hoofdletters. */
export const schoon = (code: string) => code.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4);
