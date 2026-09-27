"""Voegt vertalingen toe aan EN in vertalingen.py: python scripts/_voeg_toe.py (bewerk NIEUW eerst)."""
import json, pathlib, re

NIEUW = {
    "Rondleiding opnieuw bekijken": "Watch the tour again", "Kopieert de uitkomst": "Copies the result", "Start de timer": "Starts the timer",
    "Zes mesjes in één app: vastleggen, timers, splitten, kiezen, scanner en meten. Houd een tegel ingedrukt voor snelkoppelingen.": "Six blades in one app: capture, timers, split, choose, scanner and measure. Press and hold a tile for shortcuts.",
    "Typ, spreek in of maak een foto. Ook met de Actieknop of Siri. 'Morgen om 3 tandarts' wordt vanzelf een herinnering.": "Type, dictate or take a photo. Also with the Action button or Siri. 'Dentist tomorrow at 3' becomes a reminder by itself.",
    "Typ en het rekent": "Type and it calculates",
    "'12*3+4', '10 km in mijl', '15:00 in tokyo' of '20 min pasta': het antwoord staat er meteen onder.": "'12*3+4', '10 km in miles', '15:00 in tokyo' or '20 min pasta': the answer appears right below.",
    "Samen": "Together",
    "Deel lijstjes, houd potjes bij met vrienden, kies samen waar je gaat eten, en zie alles ook op je laptop.": "Share lists, track shared pots with friends, pick together where to eat, and see it all on your laptop too.",
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
