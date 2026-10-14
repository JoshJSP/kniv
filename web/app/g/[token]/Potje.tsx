import { afrekenen, geldFormaat, zelfdeId, type KnivRecord, type Uitgave } from "../../lib";

export default function Potje({ pot, alle }: { pot: KnivRecord; alle: KnivRecord[] }) {
  const geld = geldFormaat(pot.data?.valuta);
  const uitgaven = alle
    .filter((r) => r.soort === "uitgave" && zelfdeId((r.data as Uitgave).pot, pot.id))
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
