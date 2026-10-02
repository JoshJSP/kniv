"""Zet de gangpad-woordenlijst uit Kniv/Logica/Gangpad.swift over naar Windows en web.  python scripts/gangpad_poort.py

Gangpad.swift is de bron; dit script schrijft windows/Kniv/GangpadWoorden.cs en web/app/gangpadWoorden.ts.
Draai het na elke wijziging in de woordenlijst, anders sorteren Windows en de site anders dan de iPhone.
"""
import json
import re
from pathlib import Path

HIER = Path(__file__).resolve().parent.parent
swift = (HIER / "Kniv" / "Logica" / "Gangpad.swift").read_text("utf-8")

volgorde = re.search(r"case (groente[^\n]+)", swift).group(1).replace(" ", "").split(",")
namen = dict(re.findall(r'case \.(\w+): "([^"]+)"', swift))
blok = re.search(r"static let woorden: \[Gangpad: \[String\]\] = \[(.*?)\n    \]", swift, re.S).group(1)
woorden = {pad: re.findall(r'"([^"]*)"', lijst) for pad, lijst in re.findall(r"\.(\w+): \[(.*?)\]", blok, re.S)}
assert set(woorden) <= set(volgorde) and namen.keys() == set(volgorde), "Gangpad.swift ziet er anders uit dan verwacht"

rijen = [woorden.get(pad, []) for pad in volgorde]
kop = "Gemaakt door scripts/gangpad_poort.py uit Kniv/Logica/Gangpad.swift; niet met de hand aanpassen."

cs = [f"// {kop}", "namespace Kniv;", "", "static partial class Gangpad", "{",
      "    public static readonly string[] Namen = { " + ", ".join(json.dumps(namen[p], ensure_ascii=False) for p in volgorde) + " };", "",
      "    static readonly string[][] Woorden =", "    {"]
cs += ["        new string[] { " + ", ".join(json.dumps(w, ensure_ascii=False) for w in r) + " }," for r in rijen]
cs += ["    };", "}", ""]
(HIER / "windows" / "Kniv" / "GangpadWoorden.cs").write_text("\n".join(cs), "utf-8")

ts = [f"// {kop}", "export const NAMEN: string[] = " + json.dumps([namen[p] for p in volgorde], ensure_ascii=False) + ";", "",
      "export const WOORDEN: string[][] = " + json.dumps(rijen, ensure_ascii=False, indent=2) + ";", ""]
(HIER / "web" / "app" / "gangpadWoorden.ts").write_text("\n".join(ts), "utf-8")
print(f"{sum(map(len, rijen))} woorden in {len(volgorde)} gangpaden overgezet")
