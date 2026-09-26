import { ImageResponse } from "next/og";
import { readFile } from "node:fs/promises";
import { join } from "node:path";

export const ogSize = { width: 1200, height: 630 };

/** Preview-kaart voor WhatsApp e.d.: lemmet-icoon, titel en een regel eronder. */
export async function ogKaart(boven: string, titel: string, onder: string) {
  const icoon = await readFile(join(process.cwd(), "public/icon.png"));
  const src = `data:image/png;base64,${icoon.toString("base64")}`;
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          gap: 56,
          padding: "0 88px",
          background: "linear-gradient(135deg, #ffffff 0%, #f6ecea 100%)",
          fontFamily: "sans-serif",
        }}
      >
        <img src={src} width={220} height={220} style={{ borderRadius: 50, boxShadow: "0 20px 60px rgba(213,43,30,0.35)" }} />
        <div style={{ display: "flex", flexDirection: "column", flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 34, color: "#8e8e93" }}>{boven}</div>
          <div
            style={{
              fontSize: titel.length > 28 ? 60 : 76,
              fontWeight: 700,
              color: "#1c1c1e",
              letterSpacing: -2,
              lineHeight: 1.05,
              marginTop: 8,
              overflow: "hidden",
              maxHeight: 240,
            }}
          >
            {titel.length > 70 ? titel.slice(0, 68) + "…" : titel}
          </div>
          <div style={{ fontSize: 40, fontWeight: 600, color: "#D52B1E", marginTop: 20 }}>{onder}</div>
        </div>
      </div>
    ),
    ogSize
  );
}
