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
  data: { tekst?: string; items?: Item[]; doel?: string; titel?: string; [k: string]: unknown };
};
export type Deel = {
  titel: string;
  soort: string;
  verloopt: string | null;
  eigenaar: string | null;
  records: KnivRecord[];
  mensen?: Record<string, { naam: string; avatar: string | null }>;
};

/** Haalt een gedeelde groep op; null = onbekend of verlopen. */
export const haalDeel = cache(async (token: string): Promise<Deel | null> => {
  if (!/^[A-Za-z0-9_-]{1,100}$/.test(token)) return null;
  try {
    const res = await fetch(`${SUPABASE}/rest/v1/rpc/deelpagina`, {
      method: "POST",
      headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({ token }),
      cache: "no-store",
    });
    if (!res.ok) return null;
    return (await res.json()) as Deel | null;
  } catch {
    return null;
  }
});

/** Datum van een countdown, als die er is. */
export function doelVan(d: Deel): Date | null {
  for (const r of d.records) {
    const t = r.data?.doel;
    if (typeof t === "string" && !isNaN(Date.parse(t))) return new Date(t);
  }
  return null;
}

export function dagenTot(doel: Date): number {
  return Math.max(0, Math.ceil((doel.getTime() - Date.now()) / 86_400_000));
}

/** Korte samenvatting voor previews: "nog 12 dagen" of "5 items". */
export function samenvatting(d: Deel): string {
  const doel = doelVan(d);
  if (d.soort === "countdown" && doel) {
    const n = dagenTot(doel);
    return n === 0 ? "vandaag!" : n === 1 ? "nog 1 dag" : `nog ${n} dagen`;
  }
  const potUitgaven = d.records.filter((r) => r.soort === "uitgave");
  if (d.soort === "prik") {
    const opties = ((d.records.find((r) => r.soort === "prik")?.data?.opties as string[] | undefined) ?? []).length;
    const stemmen = d.records.filter((r) => r.soort === "prikstem").length;
    return `${opties} data · ${stemmen} ${stemmen === 1 ? "stem" : "stemmen"}`;
  }
  if (d.soort === "pot") {
    const totaal = potUitgaven.reduce((s, r) => s + (Number(r.data?.bedrag) || 0), 0);
    return `${potUitgaven.length} uitgaven · ${new Intl.NumberFormat("nl-NL", { style: "currency", currency: "EUR" }).format(totaal)}`;
  }
  const items = d.records.reduce((n, r) => n + (r.data?.items?.length || (r.data?.tekst ? 1 : 0)), 0);
  return items === 1 ? "1 item" : `${items} items`;
}
