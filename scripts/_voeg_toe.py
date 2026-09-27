"""Voegt vertalingen toe aan EN in vertalingen.py: python scripts/_voeg_toe.py (bewerk NIEUW eerst)."""
import json, pathlib, re

NIEUW = {
    "Score": "Score", "%@ wint!": "%@ wins!", "Speler toevoegen": "Add player", "Voeg toe": "Add",
    "Spelers": "Players", "Stand na %lld rondes": "Standings after %lld rounds", "Nieuwe ronde": "New round",
    "Ronde opslaan": "Save round", "Rondes": "Rounds", "Laagste score wint": "Lowest score wins",
    "Spelen tot": "Play to", "geen doel": "no target", "Nieuw spel, zelfde spelers": "New game, same players",
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
