"use client";
import { useState } from "react";

export default function Kopieer({ tekst }: { tekst: string }) {
  const [klaar, setKlaar] = useState(false);
  return (
    <div className="bron">
      <code>{tekst}</code>
      <button
        type="button"
        onClick={async () => {
          try {
            await navigator.clipboard.writeText(tekst);
            setKlaar(true);
            setTimeout(() => setKlaar(false), 1800);
          } catch {}
        }}
      >
        {klaar ? "Gekopieerd" : "Kopieer"}
      </button>
    </div>
  );
}
