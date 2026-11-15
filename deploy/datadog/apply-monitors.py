#!/usr/bin/env python3
"""Creates or updates the cynthia monitors in Datadog from monitors.json (idempotent, by name).

    DD_API_KEY=... DD_APP_KEY=... DD_SITE=datadoghq.com DD_NOTIFY=@seu-email@exemplo.com ./apply-monitors.py

DD_APP_KEY needs the monitors_write scope. DD_NOTIFY is who gets the alerts (an @email, @slack-canal...).
Standard library only: runs on the VPS or anywhere with Python 3.8+. --dry-run prints what it would do.
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from pathlib import Path

SITES = {"datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com", "datadoghq.eu", "ap1.datadoghq.com", "ap2.datadoghq.com", "ddog-gov.com"}


def request(method, url, keys, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={"DD-API-KEY": keys[0], "DD-APPLICATION-KEY": keys[1], "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.loads(r.read() or b"null")


def main():
    dry = "--dry-run" in sys.argv
    site = os.environ.get("DD_SITE", "datadoghq.com")
    if site not in SITES:
        sys.exit(f"DD_SITE desconhecido: {site}")
    notify = os.environ.get("DD_NOTIFY", "").strip()
    if not notify:
        sys.exit("Defina DD_NOTIFY (ex.: @voce@exemplo.com) para os alertas chegarem a alguém.")
    keys = (os.environ.get("DD_API_KEY", ""), os.environ.get("DD_APP_KEY", ""))
    if not dry and not all(keys):
        sys.exit("Defina DD_API_KEY e DD_APP_KEY (monitors_write).")
    api = f"https://api.{site}/api/v1/monitor"

    monitors = json.loads((Path(__file__).parent / "monitors.json").read_text())
    for m in monitors:
        m = {**m, "message": m["message"].replace("@{notify}", notify)}
        if dry:
            print(f"[dry-run] {m['name']}: {m['query']}")
            continue
        found = request("GET", f"{api}?{urllib.parse.urlencode({'name': m['name']})}", keys)
        same = [x for x in found if x.get("name") == m["name"]]
        if same:
            request("PUT", f"{api}/{same[0]['id']}", keys, m)
            print(f"atualizado: {m['name']} (#{same[0]['id']})")
        else:
            created = request("POST", api, keys, m)
            print(f"criado: {m['name']} (#{created['id']})")


if __name__ == "__main__":
    main()
