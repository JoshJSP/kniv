import type { Metadata } from "next";
import { schoon } from "../../lib";

type Props = { params: Promise<{ code: string }> };


export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const code = schoon((await params).code);
  const titel = "Kies mee in Kniv";
  const description = code.length === 4 ? `Draai samen aan het rad of stem mee. Code ${code}` : "Draai samen aan het rad of stem mee.";
  return { title: `${titel} · Kniv`, description, robots: { index: false }, openGraph: { title: titel, description } };
}

export default async function SamenKiezen({ params }: Props) {
  const code = schoon((await params).code);
  if (code.length !== 4) {
    return (
      <main className="wrap smal">
        <section className="glas midden" style={{ marginTop: "12vh" }}>
          <img src="/icon-256.png" alt="" width={64} height={64} style={{ borderRadius: 14 }} />
          <h2 style={{ marginTop: 16 }}>Deze code klopt niet</h2>
          <p className="zacht">Een code heeft vier letters. Vraag degene die hem stuurde om de link opnieuw te sturen.</p>
        </section>
      </main>
    );
  }
  return (
    <main className="wrap smal">
      <section className="glas midden" style={{ marginTop: "10vh", padding: "36px 24px" }}>
        <img src="/icon-256.png" alt="" width={88} height={88} style={{ borderRadius: 20, boxShadow: "0 14px 36px rgba(213,43,30,.3)" }} />
        <p className="zacht" style={{ margin: "20px 0 6px" }}>Je bent uitgenodigd om samen te kiezen</p>
        <h1 style={{ fontSize: "clamp(40px, 12vw, 64px)", letterSpacing: "0.12em" }}>{code}</h1>
        <a className="knop groot" href={`kniv://kies/${code}`} style={{ marginTop: 24 }}>
          Open in Kniv
        </a>
        <p className="klein" style={{ marginTop: 20, marginBottom: 0 }}>
          Of open Kniv → Kiezen → Doe mee, en typ de code. <a href="/">Nog geen Kniv?</a>
        </p>
      </section>
    </main>
  );
}
