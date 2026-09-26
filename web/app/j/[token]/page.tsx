import type { Metadata } from "next";
import { haalDeel } from "../../lib";

type Props = { params: Promise<{ token: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const deel = await haalDeel((await params).token);
  if (!deel) return { title: "Uitnodiging verlopen · Kniv", description: "Deze uitnodiging is verlopen of bestaat niet.", robots: { index: false } };
  const titel = `Doe mee met ${deel.titel || "een gedeelde lijst"}`;
  const description = deel.eigenaar ? `${deel.eigenaar} nodigt je uit in Kniv` : "Je bent uitgenodigd in Kniv";
  return {
    title: `${titel} · Kniv`,
    description,
    robots: { index: false },
    openGraph: { title: titel, description },
    twitter: { card: "summary_large_image", title: titel, description },
  };
}

export default async function Uitnodiging({ params }: Props) {
  const { token } = await params;
  const deel = await haalDeel(token);

  return (
    <main className="wrap smal">
      <section className="glas midden" style={{ marginTop: "10vh", padding: "36px 24px" }}>
        <img src="/icon.png" alt="" width={88} height={88} style={{ borderRadius: 20, boxShadow: "0 14px 36px rgba(213,43,30,.3)" }} />
        {deel ? (
          <>
            <p className="zacht" style={{ margin: "20px 0 6px" }}>
              {deel.eigenaar ? `${deel.eigenaar} heeft je uitgenodigd voor` : "Je bent uitgenodigd voor"}
            </p>
            <h1 style={{ fontSize: "clamp(30px, 8vw, 42px)", overflowWrap: "anywhere" }}>{deel.titel || "een gedeelde lijst"}</h1>
            <a className="knop groot" href={`kniv://join/${encodeURIComponent(token)}`} style={{ marginTop: 28 }}>
              Open in Kniv
            </a>
            <p className="klein" style={{ marginTop: 20, marginBottom: 0 }}>
              <a href="/">Nog geen Kniv? Zo installeer je hem</a>
            </p>
          </>
        ) : (
          <>
            <h2 style={{ marginTop: 20 }}>Deze uitnodiging werkt niet (meer)</h2>
            <p className="zacht" style={{ marginBottom: 0 }}>
              De link is verlopen of bestaat niet. Vraag degene die hem stuurde om een nieuwe.
            </p>
          </>
        )}
      </section>
    </main>
  );
}
