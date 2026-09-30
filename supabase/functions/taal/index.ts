// Leesstukjes en woordbetekenissen voor het mesje Talen, via een tekstmodel bij Groq.
// Alleen voor ingelogde gebruikers, gedeelde daglimiet met spraak (tabel ai_gebruik). De Groq-sleutel blijft hier.
import { createClient } from "npm:@supabase/supabase-js@2";

const LIMIET = 50;
const NIVEAUS = ["A1", "A1+", "A2", "A2+", "B1", "B1+", "B2", "B2+", "C1"];
const MODEL = Deno.env.get("GROQ_TEKSTMODEL") ?? "openai/gpt-oss-120b";

const fout = (tekst: string, status: number) => Response.json({ fout: tekst }, { status });
const tekst = (v: unknown) => (typeof v === "string" ? v : "");

function stukjePrompt(naam: string, niveau: string) {
  return `Je schrijft korte leesstukjes voor een Nederlandstalige die ${naam} leert op ERK-niveau ${niveau}. ` +
    `Schrijf alleen in ${naam}, nooit in het Nederlands of Engels. Mik op ongeveer 100 woorden (minimaal 80, maximaal 150), ` +
    `gewone spreektaal, zoals een leeftijdsgenoot het zou vertellen. Bij A1 en A2: korte, simpele zinnen. ` +
    `Gebruik geen woorden of grammatica boven niveau ${niveau}. ` +
    `Antwoord alleen met JSON: {"titel": korte titel in ${naam}, "tekst": het stukje met gewone leestekens en alinea's, ` +
    `"woorden": {woord: Nederlandse betekenis}}. Als sleutel in "woorden" staat ELK woord dat in de tekst voorkomt, ` +
    `precies zoals het in de tekst staat maar in kleine letters (vervoegingen en meervouden apart), ` +
    `zonder leestekens of getallen in de sleutel. Loop de tekst woord voor woord af zodat er geen enkel woord ontbreekt. ` +
    `De betekenis is kort Nederlands, passend bij hoe het woord in de tekst gebruikt wordt.`;
}

function woordPrompt(naam: string) {
  return `Je helpt een Nederlandstalige die ${naam} leert. Geef de betekenis van het woord zoals het in de zin gebruikt wordt, ` +
    `in het Nederlands: een korte vertaling, eventueel met een halve zin uitleg (grondvorm, naamval of tijd als dat helpt). ` +
    `Maximaal 20 woorden. Antwoord alleen met JSON: {"betekenis": "..."}`;
}

async function vraagGroq(systeem: string, vraag: string): Promise<Record<string, unknown> | null> {
  const body: Record<string, unknown> = {
    model: MODEL,
    messages: [{ role: "system", content: systeem }, { role: "user", content: vraag }],
    response_format: { type: "json_object" },
  };
  if (MODEL.startsWith("openai/gpt-oss")) body.reasoning_effort = "low";
  try {
    const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("GROQ_API_KEY")}`, "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!r.ok) return null;
    const j = await r.json();
    return JSON.parse(j.choices?.[0]?.message?.content ?? "");
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Alleen POST", { status: 405 });

  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await supa.auth.getUser(token);
  if (!user) return fout("Log eerst in", 401);

  // Invoer eerst controleren, pas daarna telt de vraag mee voor de daglimiet.
  const invoer = await req.json().catch(() => null);
  if (!invoer || typeof invoer !== "object") return fout("Geen geldige JSON", 400);
  const taal = tekst(invoer.taal);
  if (!/^[a-z]{2,3}$/.test(taal)) return fout("Onbekende taal", 400);
  let naam: string;
  try {
    naam = new Intl.DisplayNames(["nl"], { type: "language" }).of(taal) ?? taal;
  } catch {
    return fout("Onbekende taal", 400);
  }

  let systeem: string, vraag: string;
  if (invoer.soort === "stukje") {
    const niveau = tekst(invoer.niveau);
    const onderwerp = tekst(invoer.onderwerp).replace(/\s+/g, " ").trim().slice(0, 80);
    if (!NIVEAUS.includes(niveau)) return fout("Onbekend niveau", 400);
    if (!onderwerp) return fout("Geen onderwerp", 400);
    systeem = stukjePrompt(naam, niveau);
    vraag = `Onderwerp: ${onderwerp}`;
  } else if (invoer.soort === "woord") {
    const woord = tekst(invoer.woord).trim(), zin = tekst(invoer.zin).trim().slice(0, 400);
    if (!woord || woord.length > 60) return fout("Geen of te lang woord", 400);
    systeem = woordPrompt(naam);
    vraag = `Woord: ${woord}\nZin: ${zin}`;
  } else {
    return fout("Onbekende soort", 400);
  }

  const dag = new Date().toISOString().slice(0, 10);
  const { data: gebruik } = await supa.from("ai_gebruik").select("aantal").eq("gebruiker", user.id).eq("dag", dag).maybeSingle();
  const aantal = gebruik?.aantal ?? 0;
  if (aantal >= LIMIET) return fout("Daglimiet bereikt", 429);
  // Alleen een geslaagd antwoord telt mee voor de daglimiet.
  const tel = () => supa.from("ai_gebruik").upsert({ gebruiker: user.id, dag, aantal: aantal + 1 });

  const antwoord = await vraagGroq(systeem, vraag);
  if (invoer.soort === "woord") {
    const betekenis = tekst(antwoord?.betekenis).trim();
    if (!betekenis) return fout("Betekenis opzoeken lukte niet", 502);
    await tel();
    return Response.json({ betekenis });
  }
  const titel = tekst(antwoord?.titel).trim(), stuk = tekst(antwoord?.tekst).trim();
  if (!titel || !stuk) return fout("Stukje schrijven lukte niet", 502);
  const woorden: Record<string, string> = {};
  const lijst = antwoord?.woorden;
  if (lijst && typeof lijst === "object") {
    for (const [w, b] of Object.entries(lijst)) if (typeof b === "string" && w.trim()) woorden[w.trim().toLowerCase()] = b.trim();
  }
  await tel();
  return Response.json({ titel, tekst: stuk, woorden });
});
