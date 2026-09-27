"""Voegt vertalingen toe aan EN in vertalingen.py: python scripts/_voeg_toe.py (bewerk NIEUW eerst)."""
import json, pathlib, re

NIEUW = {
    "Bruin": "Brown", "Roze": "Pink", "Soort": "Type", "Stopt vanzelf na": "Stops by itself after", "%lld min": "%lld min",
    "Nooit": "Never", "Stopt om %@": "Stops at %@", "Achtergrondgeluid": "Background sound", "Achtergrondgeluid speelt": "Background sound playing",
    "Diep en zacht, als een waterval. Fijn om te focussen.": "Deep and soft, like a waterfall. Great for focus.",
    "Als regen op het dak. Fijn om in slaap te vallen.": "Like rain on the roof. Great for falling asleep.",
    "Als een ventilator. Dekt geluiden van buiten af.": "Like a fan. Masks noise from outside.",
    "Lopen": "Walk", "Fiets": "Bike", "OV": "Transit", "Auto": "Car", "Vervoer": "Transport",
    "Ik ben er rond %@.": "I'll be there around %@.", "Naar %@, over %lld min": "To %@, in %lld min", "Stuur dit": "Send this",
    "Waar ga je heen?": "Where are you going?", "Zoek een adres of plek": "Search an address or place", "Ik ben er om…": "I'll be there at…",
    "Niets gevonden. Probeer het met een plaatsnaam erbij.": "Nothing found. Try adding a town name.",
    "Geen OV-tijden voor deze route. Probeer lopen of fiets.": "No transit times for this route. Try walking or cycling.",
    "Kon de route niet berekenen. Staat locatie aan?": "Couldn't calculate the route. Is location on?",
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
