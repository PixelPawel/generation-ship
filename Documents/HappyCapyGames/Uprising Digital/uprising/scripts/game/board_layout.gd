class_name BoardLayout
extends RefCounted

## Lightweight, Milestone-1-scoped board description: enough structured data
## to build a real editable 3D scene from a specific setup configuration.
## This is NOT the full networked GameState (that's Milestone 2) - it holds
## no turn/phase/resource state, just "what piece sits on which hex".

var capital_coord: Vector2i = Vector2i.ZERO
var capital_garrison_count: int = 0

## Interior hexes: unexplored face-down Core "Normal" hexes filling the rest
## of the board interior (not Home/Sea Tower/Capital).
var interior_coords: Array[Vector2i] = []
var interior_hex_cards: Dictionary = {}  # Vector2i -> HexCard

var home_coords: Array[Vector2i] = []
var home_hex_cards: Dictionary = {}      # Vector2i -> HexCard
var home_factions: Dictionary = {}       # Vector2i -> String (faction name)

var sea_tower_coords: Array[Vector2i] = []
var sea_tower_hex_cards: Dictionary = {}  # Vector2i -> HexCard

## coord -> Garrison stack count (1-3), NOT including the Capital (tracked
## separately above since the Capital always carries its own baseline 3,
## per rulebook Setup step 6 - that baseline isn't in the TTS setup script
## at all, it's presumably a fixed feature of the Capital board piece).
var garrison_counts: Dictionary = {}

var curse_coords: Array[Vector2i] = []

## coord -> Skeleton count (1-2 normally, 3 auto-converts to a Horde).
var skeleton_counts: Dictionary = {}
