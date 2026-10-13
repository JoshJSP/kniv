"use client";
import { useEffect } from "react";

/** Storing bij Supabase of het netwerk: niet doen alsof de link verlopen is, en het zelf opnieuw proberen. */
export default function Fout({ reset }: { reset: () => void }) {
  useEffect(() => {
    const id = setTimeout(reset, 10_000);
    return () => clearTimeout(id);
  }, [reset]);
  return (
    <main className="wrap smal">
      <section className="glas midden" style={{ marginTop: "12vh" }}>
        <img src="/icon.png" alt="" width={64} height={64} style={{ borderRadius: 14 }} />
        <h2 style={{ marginTop: 16 }}>Even geen verbinding</h2>
        <p className="zacht">Kniv kan de lijst nu niet ophalen. Hij probeert het zo opnieuw.</p>
        <button className="knop" onClick={reset} style={{ marginTop: 12 }}>Opnieuw proberen</button>
      </section>
    </main>
  );
}
