import type { Metadata, Viewport } from "next";
import { SITE } from "./lib";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(SITE),
  title: "Kniv",
  description: "Zes handige mesjes in één app: vastleggen, timers, splitten, kiezen, scannen en meten.",
  icons: { icon: "/icon.png", apple: "/icon.png" },
  openGraph: { siteName: "Kniv", locale: "nl_NL", type: "website" },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f2f2f7" },
    { media: "(prefers-color-scheme: dark)", color: "#000000" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="nl">
      <body>{children}</body>
    </html>
  );
}
