import type { KnivRecord } from "../../lib";

type Uitgave = { omschrijving?: string; bedrag?: number; betaaldDoor?: string; voor?: string[]; datum?: string; pot?: string };

/** Zelfde regels als de app (Kniv/Logica/Rekenen.swift): saldo per persoon, dan zo min mogelijk overboekingen. */
function afrekenen(uitgaven: Uitgave[]) {
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

export default function Potje({ pot, alle }: { pot: KnivRecord; alle: KnivRecord[] }) {
  const valuta = typeof pot.data?.valuta === "string" ? pot.data.valuta : "EUR";
  const geld = new Intl.NumberFormat("nl-NL", { style: "currency", currency: valuta });
  const uitgaven = alle
    .filter((r) => r.soort === "uitgave" && (r.data as Uitgave).pot === pot.id)
    .map((r) => r.data as Uitgave)
    .sort((a, b) => (b.datum ?? "").localeCompare(a.datum ?? ""));
  const totaal = uitgaven.reduce((s, u) => s + (u.bedrag ?? 0), 0);
  const betalingen = afrekenen(uitgaven);

  return (
    <>
      <section className="glas midden">
        <div className="teller">{geld.format(totaal)}</div>
        <p className="zacht" style={{ marginTop: 8 }}>
          {uitgaven.length === 1 ? "1 uitgave" : `${uitgaven.length} uitgaven`}
          {Array.isArray(pot.data?.leden) && ` · ${(pot.data.leden as string[]).join(", ")}`}
        </p>
      </section>

      <section className="glas">
        <h2 style={{ marginTop: 0, fontSize: 20 }}>Afrekenen</h2>
        {betalingen.length === 0 ? (
          <p className="zacht" style={{ margin: 0 }}>Iedereen staat quitte.</p>
        ) : (
          <ul className="lijst">
            {betalingen.map((b, i) => (
              <li key={i}>
                <span>{`${b.van} → ${b.naar}`}</span>
                <strong>{geld.format(b.bedrag)}</strong>
              </li>
            ))}
          </ul>
        )}
      </section>

      {uitgaven.length > 0 && (
        <section className="glas">
          <h2 style={{ marginTop: 0, fontSize: 20 }}>Uitgaven</h2>
          <ul className="lijst">
            {uitgaven.map((u, i) => (
              <li key={i}>
                <span>
                  {u.omschrijving || "Uitgave"}
                  <span className="zacht" style={{ display: "block", fontSize: 13 }}>{u.betaaldDoor} betaalde</span>
                </span>
                <span>{geld.format(u.bedrag ?? 0)}</span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </>
  );
}
