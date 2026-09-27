"""Voegt vertalingen toe aan EN in vertalingen.py: python scripts/_voeg_toe.py (bewerk NIEUW eerst)."""
import json, pathlib, re

NIEUW = {
    "Kenteken": "Licence plate", "Opzoeken": "Look up", "Kenteken fotograferen": "Photograph licence plate",
    "Gegevens van de RDW (open data).": "Data from the Dutch vehicle authority (RDW, open data).",
    "Geen kenteken gevonden op de foto.": "No licence plate found in the photo.", "APK tot %@": "MOT valid until %@",
    "Verzekerd": "Insured", "Niet verzekerd": "Not insured", "Kilometerstand: %@": "Odometer: %@",
    "Er loopt een terugroepactie. Vraag de dealer ernaar.": "There's an open recall. Ask the dealer about it.",
    "Verbruik %@ l/100 km (1 op %@)": "Consumption %@ l/100 km", "Nieuwprijs %@": "Price when new %@",
    "Staat in Kniv": "Saved in Kniv", "Herinner me een maand voor de APK": "Remind me a month before the MOT",
    "Dit kenteken kent de RDW niet.": "The RDW doesn't know this plate.", "De RDW is even niet bereikbaar.": "The RDW can't be reached right now.",
}

pad = pathlib.Path(__file__).with_name("vertalingen.py")
s = pad.read_text(encoding="utf-8")
bestaand = set(re.findall(r'"((?:[^"\\]|\\.)*)":', s))
regels = [f"    {json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)},"
          for k, v in NIEUW.items() if k not in bestaand]
eind = s.index("\n}\n\nSIRI")
s = s[:eind] + "\n" + "\n".join(regels) + s[eind:]
pad.write_text(s, encoding="utf-8")
print(f"{len(regels)} nieuw")
