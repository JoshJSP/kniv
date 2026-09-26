"""Stuurt Josh een korte Kniv-update via de VESPER-Telegrambot. python scripts/meld.py "tekst"

Token en chat komen uit VESPER, net als bij ~/.claude/hooks/klaar-melden.py.
"""
import sys
import urllib.parse
import urllib.request
from pathlib import Path

VESPER = Path.home() / "Vesper"
token = next(r.split("=", 1)[1].strip().strip("\"'") for r in (VESPER / ".env").read_text("utf-8").splitlines()
             if r.strip().startswith("TELEGRAM_TOKEN"))
chat = (VESPER / "data" / "telegram_owner.txt").read_text("utf-8").strip()
data = urllib.parse.urlencode({"chat_id": chat, "text": "🔪 Kniv\n\n" + " ".join(sys.argv[1:])}).encode()
print(urllib.request.urlopen(f"https://api.telegram.org/bot{token}/sendMessage", data=data, timeout=15).status)
