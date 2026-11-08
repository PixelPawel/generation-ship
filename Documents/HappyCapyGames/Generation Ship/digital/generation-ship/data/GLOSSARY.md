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
| Danger | Gefahr | Pericolo | Zagrożenie | Peligro | Danger |
| Advanced Sector | Fortgeschrittener Sektor | Settore Avanzato | Sektor zaawansowany | Sector Avanzado | Secteur Avancé |

## Card states

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Faceup | aufgedeckt / offen | a faccia in su | odkryta | boca arriba | face visible |
| Facedown | verdeckt | a faccia in giù | zakryta | boca abajo | face cachée |

## Supply colors

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Supply (generic) | Vorrat / Vorräte | risorsa / risorse | zasób / zasoby | suministro | matériel / matériels |
| Dust | Staub | Polvere | Pył | Polvo | Poussière |
| Metals | Metalle | Metalli | Metale | Metales | Métaux |
| Liquids | Wasser | Liquidi | Płyny | Líquidos | Liquides |
| Organix | Organix | Organix | Organix | Organix | Organix |
| Electrix | Electrix | Electrix | Electrix | Electrix | Electrix |
| Thrust | Schub | Spinta | Napęd | Empuje | Poussée |

Note: German "Liquids" was deliberately shortened from the literal
Flüssigkeiten to Wasser — Flüssigkeiten was too long for the supply
label/icon UI (see commit 626e32a).

Note: French "Supply" is "matériel" (masculine: "1 matériel stocké",
"les matériels stockés", "Chaîne de Matériel"), not "ressource". It had
been "ressource" on cards/aids/game data and "matériel" in the rule book;
all were unified to "matériel" on 2026-09-29.

## Actions

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Fuse | fusionieren | fondere | połączyć | fusionar | fusionner |
| Recycle | recyceln | riciclare | zrecykluj / recykling / poddać recyklingowi | reciclar | recycler |
| Archive | archivieren | archiviare | zarchiwizować | archivar | archiver |
| Research | Forschung / forschen | ricerca | badania | investigación | recherche |
| Pass | passen | passare | pasować / pasuj | pasar | passer |
| Bid | Gebot / bieten | offerta | oferta / licytacja | puja | enchère |
| Auction | Auktion | asta | licytacja / aukcja | subasta | enchère |
| Store (supply) | lagern | immagazzinare | zmagazynować | almacenar | stocker |
| Discard | abwerfen | scartare | odrzucić | descartar | défausser |

Note (2026-11-08 audit): German "Store" is "lagern" everywhere (cards, rule book, UI: "Gelagerte
Vorräte"); the UI had used "speichern", which reads as saving a file.

Note: "Archive" replaced "Tuck" (2026-10-01): a card placed faceup or facedown under a sector.
Before, each language used several verbs for it (DE ablegen/verstauen/legen ... unter, ES colocar/guardar,
FR empiler/ranger, IT mettere (da parte)/ripiegare, PL odłożyć/podłożyć); all now use the one verb above.
German takes the dative with it: "unter diesem Sektor" (not "diesen"); Polish uses the perfective
imperative "Zarchiwizuj" on cards.

Note: Polish "Recycle" (2026-10-25): the cards say "zrecykluj" (recyklować, zrecyklowane),
the rule book "Recykling" and the game UI "poddaj recyklingowi". The cards had said "zutylizuj",
and this glossary "Odzysk", which nothing used. Polish "Danger" is "Zagrożenie" and "Auction"
"licytacja" on cards and in the rule book. Italian "faceup / facedown" is "a faccia in su / in giù"
and an Italian Tech card is a "carta Tech" (not "carta tecnologia").

Note: French uses "enchère" for both Bid and Auction — there's no separate
term, so translate by context rather than a 1:1 word swap.

## UI / meta

| EN | DE | IT | PL | ES | FR |
|---|---|---|---|---|---|
| Market | Markt | Mercato | Rynek | Mercado | Marché |
| Star | Stern | stella | gwiazdka / gwiazda | estrella | étoile |
| Rulebook | Regelbuch | Regolamento | Instrukcja | Reglamento | Livret de règles |
| Pause Menu | Pausenmenü | Menu di pausa | Menu pauzy | Menú de pausa | Menu pause |
| Settings | Einstellungen | Impostazioni | Ustawienia | Ajustes | Paramètres |
| Language | Sprache | Lingua | Język | Idioma | Langue |
| Done | Fertig | Fatto | Gotowe | Hecho | Terminé |
| Generation (round) | Generation | Generazione | Pokolenie | Generación | Génération |
| Always (card type) | Immer | Sempre | Zawsze | Siempre | Toujours |
| Shuttle (Fleet) | Shuttle | navetta | wahadłowiec (rule book: Prom) | transbordador | navette |
| Slot (sector space) | Platz | slot | miejsce | casilla | emplacement |
| Interfleet Comms | Flotten Kommunikation | Comunicazioni Interflotta | Łączność Międzyflotowa | Comunicaciones Interflota | Comms Interflotte |

Card names in UI texts: always the printed card's name in that language (data/Card Text Translations.csv,
`<deck>:<No.>:name`), e.g. Interfleet Comms above (it used to be kept in English; the printed cards
translate it, 2026-11-08). The UI strings were aligned with the printed names on 2026-11-08.
