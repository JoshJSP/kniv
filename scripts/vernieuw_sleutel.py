"""Nieuwe Supabase-beheersleutel instellen, in één keer.  python scripts/vernieuw_sleutel.py

Maak eerst een sleutel op https://supabase.com/dashboard/account/tokens (org "Kniv", Full access,
anders krijg je 403). Plak hem hier: het script test hem, zet hem in ~/.kniv/supabase.env en in de
GitHub-geheimen (voor de functies-workflow en de sleutelwachter), en onthoudt de vervaldatum.
"""
import datetime
import getpass
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

PROJECT = "ykptlgckqppgxirtndch"
ENV = Path.home() / ".kniv" / "supabase.env"

sleutel = getpass.getpass("Nieuwe sleutel (sbp_…, je ziet hem niet tijdens het plakken): ").strip()
if not sleutel.startswith("sbp_"):
    sys.exit("Dat lijkt geen Supabase-beheersleutel (die begint met sbp_).")

try:
    vraag = urllib.request.Request(f"https://api.supabase.com/v1/projects/{PROJECT}",
                                   headers={"Authorization": f"Bearer {sleutel}", "User-Agent": "kniv-beheer"})
    urllib.request.urlopen(vraag, timeout=20)
except urllib.error.HTTPError as e:
    sys.exit(f"Supabase weigert de sleutel ({e.code}). Heeft hij org Kniv en Full access?")
print("Sleutel werkt.")

dagen = input("Over hoeveel dagen verloopt hij? (Enter = 30): ").strip() or "30"
verloopt = (datetime.date.today() + datetime.timedelta(days=int(dagen))).isoformat()

regels = ENV.read_text("utf-8").splitlines() if ENV.exists() else []
regels = [r for r in regels if not r.startswith("SUPABASE_ACCESS_TOKEN=")] + [f"SUPABASE_ACCESS_TOKEN={sleutel}"]
ENV.write_text("\n".join(regels) + "\n", "utf-8")
print(f"Bijgewerkt: {ENV}")

subprocess.run(["gh", "secret", "set", "SUPABASE_ACCESS_TOKEN", "-R", "JoshJSP/kniv"], input=sleutel, text=True, check=True)
subprocess.run(["gh", "variable", "set", "SLEUTEL_VERLOOPT", "-R", "JoshJSP/kniv", "--body", verloopt], check=True)
print(f"GitHub bijgewerkt. De wachter meldt zich weer een week voor {verloopt}.")
