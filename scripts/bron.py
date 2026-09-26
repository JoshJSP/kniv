"""Zet een nieuwe build bovenaan de SideStore-bron (apps.json in kniv-releases).

python3 scripts/bron.py <apps.json> <versie> <build> <download-url> <bytes> <versie.json>
SideStore neemt de bovenste versie als nieuwste; version en buildVersion moeten
exact kloppen met de Info.plist, anders blijft SideStore 'update' aanbieden.
"""
import datetime
import json
import sys

pad, versie, build, url, grootte, versiejson = sys.argv[1:7]
info = json.load(open(versiejson, encoding="utf-8"))
bron = json.load(open(pad, encoding="utf-8"))
app = bron["apps"][0]

nieuw = {
    "version": versie,
    "buildVersion": build,
    "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "localizedDescription": f"Kniv {info['mesnaam']}\n" + "\n".join("• " + r for r in info["nieuw"]),
    "downloadURL": url,
    "size": int(grootte),
    "minOSVersion": "18.0",
}
app["versions"] = [nieuw] + [v for v in app.get("versions", []) if v.get("buildVersion") != build][:9]
app["version"], app["versionDate"], app["downloadURL"], app["size"] = versie, nieuw["date"], url, nieuw["size"]

with open(pad, "w", encoding="utf-8") as f:
    json.dump(bron, f, ensure_ascii=False, indent=2)
print(f"Bron bijgewerkt: {versie} ({build})")
