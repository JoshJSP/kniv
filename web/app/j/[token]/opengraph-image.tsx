import { haalDeel } from "../../lib";
import { ogKaart, ogSize } from "../../og";

export const size = ogSize;
export const contentType = "image/png";
export const alt = "Uitnodiging voor Kniv";

export default async function Image({ params }: { params: Promise<{ token: string }> }) {
  const deel = await haalDeel((await params).token);
  if (!deel) return ogKaart("Kniv", "Uitnodiging verlopen", "Vraag om een nieuwe link");
  return ogKaart(deel.eigenaar ? `${deel.eigenaar} nodigt je uit` : "Uitnodiging", deel.titel || "Gedeelde lijst", "Doe mee in Kniv");
}
