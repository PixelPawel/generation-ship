"""Uploads the cards' current texts (English + DE/ES/FR/IT/PL, per name / flavor / effect) to the API
server, where the "GS Translation Comments" Google Sheet's daily update reads them (admin endpoint
/v1/comments/cards) to show each comment next to the English and the translated text.

    python tools/upload_card_texts.py            # build + upload
    python tools/upload_card_texts.py --dry-run  # only build, print a summary

Rerun after card texts or translations change. Needs the VPS ssh key (~/.ssh/hcg_vps).
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
VPS = "root@179.236.229.160"
KEY = os.path.join(os.path.expanduser("~"), ".ssh", "hcg_vps")
REMOTE = "/opt/hcg-api/data/card_texts.json"
LANGS = ["DE", "ES", "FR", "IT", "PL"]
FIELDS = ["name", "flavor", "effect"]


def build() -> dict:
    # the comments report tool already knows how to read the card sheets and translations
    spec = importlib.util.spec_from_file_location("tcr", os.path.join(HERE, "translation_comments_report.py"))
    tcr = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tcr)
    en, tr = tcr.card_texts()
    out = {}
    for fid, row in en.items():
        card = {"EN": {f: tcr.part_text(row, f) for f in FIELDS}}
        for lang in LANGS:
            card[lang] = {f: tcr.part_text(tr.get((lang, fid)), f) for f in FIELDS}
        out[fid] = card
    return out


def main() -> None:
    cards = build()
    print(len(cards), "cards")
    if "--dry-run" in sys.argv:
        return
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as f:
        json.dump(cards, f, ensure_ascii=False)
        tmp = f.name
    try:
        subprocess.run(["scp", "-q", "-i", KEY, tmp, VPS + ":" + REMOTE], check=True)
    finally:
        os.remove(tmp)
    print("uploaded to", REMOTE)


if __name__ == "__main__":
    main()
