# Translation Glossary

Key game terms and how they're rendered in each supported language, extracted
from the actual committed translations in `data/UI Strings.csv`,
`scripts/game/card_data.gd` (supply colors), and `data/translations/*.csv`
(card text). Keep this file in sync when any of these terms' translations
change — it's the source of truth for consistent terminology across new
strings.

## Card types

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Sector | Sektor | Settore | Sektor | Sector | Secteur |
| Tech (card) | Tech | Tech | Tech | Tecnología | Tech |
| Expedition | Expedition | Spedizione | Ekspedycja | Expedición | Expédition |
| Dust Sector | Staub-Sektor | Settore Polvere | Sektor Pyłu | Sector de Polvo | Secteur Poussière |
| Destination | Ziel | destinazione | cel | destino | destination |

Danger and Advanced Sector card types have no standalone UI string yet (no
tutorial/tooltip text references them by name) — translate on first use,
matching this table's tone.

## Supply colors

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Supply (generic) | Vorrat / Vorräte | risorsa / risorse | zasób / zasoby | suministro | ressource |
| Dust | Staub | Polvere | Pył | Polvo | Poussière |
| Metals | Metalle | Metalli | Metale | Metales | Métaux |
| Liquids | Wasser | Liquidi | Płyny | Líquidos | Liquides |
| Organix | Organix | Organix | Organix | Organix | Organix |
| Electrix | Electrix | Electrix | Electrix | Electrix | Electrix |
| Thrust | Schub | Spinta | Napęd | Empuje | Poussée |

Note: German "Liquids" was deliberately shortened from the literal
Flüssigkeiten to Wasser — Flüssigkeiten was too long for the supply
label/icon UI (see commit 626e32a).

## Actions

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Fuse | verschmelzen | fondere | połączyć | fusionar | fusionner |
| Recycle | recyceln | riciclare | poddać recyklingowi | reciclar | recycler |
| Research | Forschung / forschen | ricerca | badania | investigación | recherche |
| Pass | passen | passare | pasować | pasar | passer |
| Bid | Gebot / bieten | offerta | oferta / licytacja | puja | enchère |
| Auction | Auktion | asta | aukcja | subasta | enchère |

Note: French uses "enchère" for both Bid and Auction — there's no separate
term, so translate by context rather than a 1:1 word swap.

## UI / meta

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Market | Markt | Mercato | Rynek | Mercado | Marché |
| Star | Stern | stella | gwiazdka | estrella | étoile |
| Rulebook | Regelbuch | Regolamento | Instrukcja | Reglamento | Livret de règles |
| Pause Menu | Pausenmenü | Menu di pausa | Menu pauzy | Menú de pausa | Menu pause |
| Settings | Einstellungen | Impostazioni | Ustawienia | Ajustes | Paramètres |
| Language | Sprache | Lingua | Język | Idioma | Langue |
| Done | Fertig | Fatto | Gotowe | Hecho | Terminé |
| Interfleet Comms | Interfleet Comms | Interfleet Comms | Interfleet Comms | Interfleet Comms | Interfleet Comms |

Interfleet Comms is a proper noun/brand term and is kept untranslated in
every language.
