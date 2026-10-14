import { ogKaart, ogSize } from "../../og";
import { schoon } from "../../lib";

export const size = ogSize;
export const contentType = "image/png";
export const alt = "Samen kiezen in Kniv";

/** Preview in WhatsApp: de code groot, net als op de pagina. */
export default async function Image({ params }: { params: Promise<{ code: string }> }) {
  const code = schoon((await params).code);
  if (code.length !== 4) return ogKaart("Kniv", "Code klopt niet", "Vraag om de link opnieuw");
  return ogKaart("Kies mee in Kniv", code, "Draai samen aan het rad of stem mee");
}
