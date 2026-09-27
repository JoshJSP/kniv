import type { KnivRecord } from "../../lib";

type Stem = { prik?: string; naam?: string; ja?: string[] };

export default function Prikje({ prik, alle }: { prik: KnivRecord; alle: KnivRecord[] }) {
  const opties = ((prik.data?.opties as string[] | undefined) ?? []).slice().sort();
  const stemmen = alle.filter((r) => r.soort === "prikstem" && (r.data as Stem).prik === prik.id).map((r) => r.data as Stem);
  const aantal = (d: string) => stemmen.filter((s) => s.ja?.includes(d)).length;
  const top = Math.max(0, ...opties.map(aantal));
  const tijd = (d: string) =>
    new Date(d).toLocaleString("nl-NL", { weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit", timeZone: "Europe/Amsterdam" });

  return (
    <section className="glas">
      <h2 style={{ marginTop: 0, fontSize: 20 }}>Wanneer kan iedereen?</h2>
      <ul className="lijst">
        {opties.map((d) => {
          const wie = stemmen.filter((s) => s.ja?.includes(d)).map((s) => s.naam).filter(Boolean);
          const beste = top > 0 && aantal(d) === top;
          return (
            <li key={d}>
              <span>
                {beste ? "★ " : ""}
                {tijd(d)}
                {wie.length > 0 && <span className="zacht" style={{ display: "block", fontSize: 13 }}>{wie.join(", ")}</span>}
              </span>
              <strong style={beste ? { color: "var(--rood)" } : undefined}>{aantal(d)}</strong>
            </li>
          );
        })}
      </ul>
      <p className="zacht klein" style={{ marginBottom: 0 }}>
        {stemmen.length === 1 ? "1 persoon heeft gestemd" : `${stemmen.length} mensen hebben gestemd`}
      </p>
    </section>
  );
}
