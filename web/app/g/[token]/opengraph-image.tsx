import { haalDeel, samenvatting } from "../../lib";
import { ogKaart, ogSize } from "../../og";

export const size = ogSize;
export const contentType = "image/png";
export const alt = "Gedeeld via Kniv";

export default async function Image({ params }: { params: Promise<{ token: string }> }) {
  const deel = await haalDeel((await params).token);
  if (!deel) return ogKaart("Kniv", "Link verlopen", "Vraag om een nieuwe link");
  return ogKaart(deel.eigenaar ? `Van ${deel.eigenaar}` : "Gedeeld", deel.titel || "Gedeeld", samenvatting(deel));
}
