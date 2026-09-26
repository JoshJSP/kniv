"""Stuurt de nieuwste Kniv.ipa naar Josh via de VESPER-Telegrambot. python scripts/stuur_ipa.py"""
import json
import subprocess
import tempfile
import urllib.request
import uuid
from pathlib import Path

VESPER = Path.home() / "Vesper"
token = next(r.split("=", 1)[1].strip().strip("\"'") for r in (VESPER / ".env").read_text("utf-8").splitlines()
             if r.strip().startswith("TELEGRAM_TOKEN"))
chat = (VESPER / "data" / "telegram_owner.txt").read_text("utf-8").strip()

bron = json.load(urllib.request.urlopen("https://raw.githubusercontent.com/JoshJSP/kniv-releases/main/apps.json?nocache", timeout=20))
versie = bron["apps"][0]["versions"][0]
map_ = Path(tempfile.mkdtemp())
tag = versie["downloadURL"].split("/download/")[1].split("/")[0]
subprocess.run(["gh", "release", "download", tag, "-R", "JoshJSP/kniv-releases", "-p", "Kniv.ipa", "-D", str(map_)], check=True)

grens = uuid.uuid4().hex
def veld(n, w): return f"--{grens}\r\nContent-Disposition: form-data; name=\"{n}\"\r\n\r\n{w}\r\n".encode()
body = (veld("chat_id", chat) + veld("caption", f"Kniv {versie['version']}. Tik op het bestand → Deel → SideStore.")
        + f"--{grens}\r\nContent-Disposition: form-data; name=\"document\"; filename=\"Kniv.ipa\"\r\nContent-Type: application/octet-stream\r\n\r\n".encode()
        + (map_ / "Kniv.ipa").read_bytes() + f"\r\n--{grens}--\r\n".encode())
req = urllib.request.Request(f"https://api.telegram.org/bot{token}/sendDocument", data=body,
                             headers={"Content-Type": f"multipart/form-data; boundary={grens}"})
print(versie["version"], urllib.request.urlopen(req, timeout=60).status)
