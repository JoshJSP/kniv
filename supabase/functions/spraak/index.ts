// Spraak uitschrijven met Whisper bij Groq, als de iPhone het zelf niet goed verstond.
// Alleen voor ingelogde gebruikers, maximaal LIMIET keer per dag (tabel ai_gebruik). De Groq-sleutel blijft hier.
import { createClient } from "npm:@supabase/supabase-js@2";

const LIMIET = 50;

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Alleen POST", { status: 405 });

  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: { user } } = await supa.auth.getUser(token);
  if (!user) return Response.json({ fout: "Log eerst in" }, { status: 401 });

  // Opname eerst controleren; alleen een geslaagd antwoord telt mee voor de daglimiet (net als bij taal).
  const audio = await req.arrayBuffer();
  if (audio.byteLength === 0 || audio.byteLength > 24 * 1024 * 1024) return Response.json({ fout: "Geen of te grote opname" }, { status: 400 });

  // Plek nemen in één keer (ook bij veel verzoeken tegelijk); mislukt het uitschrijven, dan gaat hij terug.
  const dag = new Date().toISOString().slice(0, 10);
  const { data: plek, error } = await supa.rpc("ai_neem", { g: user.id, d: dag, max: LIMIET });
  if (error) return Response.json({ fout: "Even niet beschikbaar" }, { status: 503 });
  if (plek !== true) return Response.json({ fout: "Daglimiet bereikt" }, { status: 429 });

  const form = new FormData();
  form.append("file", new Blob([audio], { type: req.headers.get("Content-Type") ?? "audio/m4a" }), "spraak.m4a");
  form.append("model", "whisper-large-v3-turbo");
  form.append("response_format", "json");
  const taal = new URL(req.url).searchParams.get("taal");
  if (taal) form.append("language", taal);

  try {
    const groq = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
      method: "POST",
      headers: { Authorization: `Bearer ${Deno.env.get("GROQ_API_KEY")}` },
      body: form,
      signal: AbortSignal.timeout(45_000),
    });
    if (!groq.ok) throw new Error(`groq ${groq.status}`);
    const { text } = await groq.json();
    return Response.json({ tekst: (text ?? "").trim() });
  } catch {
    await supa.rpc("ai_terug", { g: user.id, d: dag });
    return Response.json({ fout: "Uitschrijven lukte niet" }, { status: 502 });
  }
});
