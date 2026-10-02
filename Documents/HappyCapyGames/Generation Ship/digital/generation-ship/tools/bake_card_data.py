"""Regenerate scripts/game/card_data_baked.gd from the card CSVs in data/.

The baked copy is CardDatabase's fallback when an export doesn't ship the
CSVs. Rerun after editing any of the five card sheets below.
"""
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SHEETS = [
    ("ADVANCED_SECTORS", "Advanced Sectors"),
    ("DUST_SECTORS", "Dust Sectors"),
    ("TECHS", "Techs"),
    ("EXPEDITIONS", "Expeditions"),
    ("PROMOS", "Promos"),
]


def gd_string(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\r\n", "\n").replace("\n", r"\n") + '"'


lines = ["# Auto-generated from the card design CSVs – do not edit by hand.", "class_name CardDataBaked", ""]
for const, sheet in SHEETS:
    path = os.path.join(ROOT, "data", f"Generation Ship Full Card Details - {sheet}.csv")
    with open(path, encoding="utf-8-sig", newline="") as f:
        lines.append(f"const {const}: String = {gd_string(f.read())}")
out = os.path.join(ROOT, "scripts", "game", "card_data_baked.gd")
with open(out, "w", encoding="utf-8-sig", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("wrote", out)
