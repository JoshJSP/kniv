import type { Metadata } from "next";
import { dagenTot, doelVan, haalDeel, samenvatting, type KnivRecord } from "../../lib";
import Ververs from "./Ververs";

type Props = { params: Promise<{ token: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const deel = await haalDeel((await params).token);
  if (!deel) return { title: "Link verlopen · Kniv", description: "Deze link is verlopen of bestaat niet.", robots: { index: false } };
  const titel = deel.titel || "Gedeeld via Kniv";
  const description = [deel.eigenaar && `Gedeeld door ${deel.eigenaar}`, samenvatting(deel)].filter(Boolean).join(" · ");
  return {
    title: `${titel} · Kniv`,
    description,
    robots: { index: false },
    openGraph: { title: titel, description },
    twitter: { card: "summary_large_image", title: titel, description },
  };
}

function Bol({ naam, avatar }: { naam: string | null; avatar: string | null }) {
  if (avatar) return <img className="bol" src={avatar} alt={naam ?? ""} title={naam ?? ""} referrerPolicy="no-referrer" />;
  return (
    <span className="bol" title={naam ?? ""} aria-label={naam ?? ""}>
      {(naam?.trim()[0] ?? "?").toUpperCase()}
    </span>
  );
}

function Record({ r }: { r: KnivRecord }) {
  const items = [...(r.data?.items ?? [])].sort((a, b) => (a.volgorde ?? 0) - (b.volgorde ?? 0));
  const tekst = typeof r.data?.tekst === "string" ? r.data.tekst.trim() : "";
  if (!tekst && !items.length) return null;
  return (
    <section className="glas">
      {tekst && <p className="notitie-tekst">{tekst}</p>}
      {items.length > 0 && (
        <ul className="lijst" style={tekst ? { marginTop: 12 } : undefined}>
          {items.map((it, i) => (
            <li key={i}>
              <span>{it.tekst}</span>
              {/* ponytail: de rpc geeft alleen naam/avatar van de laatste wijziger per record, niet per item. */}
              <Bol naam={r.door} avatar={r.avatar} />
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export default async function Gedeeld({ params }: Props) {
  const deel = await haalDeel((await params).token);

  if (!deel) {
    return (
      <main className="wrap smal">
        <section className="glas midden" style={{ marginTop: "12vh" }}>
          <img src="/icon.png" alt="" width={64} height={64} style={{ borderRadius: 14 }} />
          <h2 style={{ marginTop: 16 }}>Deze link werkt niet (meer)</h2>
          <p className="zacht">De link is verlopen of bestaat niet. Vraag degene die hem stuurde om een nieuwe.</p>
        </section>
      </main>
    );
  }

  const doel = deel.soort === "countdown" ? doelVan(deel) : null;
  const notities = deel.records.filter((r) => r.soort === "notitie");

  return (
    <main className="wrap smal stapel">
      <header>
        <div className="kop">
          <img src="/icon.png" alt="" width={44} height={44} />
          <h1>{deel.titel || "Gedeeld"}</h1>
        </div>
        <p className="zacht" style={{ margin: "12px 0 0", display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
          {deel.eigenaar && <span>Van {deel.eigenaar}</span>}
          <Ververs />
        </p>
      </header>

      {doel && (
        <section className="glas midden">
          <div className="teller">{dagenTot(doel)}</div>
          <p className="zacht" style={{ marginTop: 8 }}>
            {dagenTot(doel) === 1 ? "dag" : "dagen"} tot{" "}
            {doel.toLocaleDateString("nl-NL", { weekday: "long", day: "numeric", month: "long", timeZone: "Europe/Amsterdam" })}
          </p>
        </section>
      )}

      {notities.map((r) => (
        <Record key={r.id} r={r} />
      ))}

      {!doel && notities.length === 0 && (
        <section className="glas midden">
          <p className="zacht" style={{ margin: 0 }}>
            Hier staat nog niets.
          </p>
        </section>
      )}
    </main>
  );
}
