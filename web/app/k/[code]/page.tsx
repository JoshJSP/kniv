import type { Metadata } from "next";

type Props = { params: Promise<{ code: string }> };

const schoon = (code: string) => code.toUpperCase().replace(/[^A-Z]/g, "").slice(0, 4);

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const code = schoon((await params).code);
  const titel = "Kies mee in Kniv";
  const description = `Draai samen aan het rad of stem mee. Code ${code}`;
  return { title: `${titel} · Kniv`, description, robots: { index: false }, openGraph: { title: titel, description } };
}

export default async function SamenKiezen({ params }: Props) {
  const code = schoon((await params).code);
  return (
    <main className="wrap smal">
      <section className="glas midden" style={{ marginTop: "10vh", padding: "36px 24px" }}>
        <img src="/icon.png" alt="" width={88} height={88} style={{ borderRadius: 20, boxShadow: "0 14px 36px rgba(213,43,30,.3)" }} />
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
