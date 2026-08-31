@tool
extends Node3D
## First-pass staging scene: lays TheMap.jpg down as the table, then places
## one instance of every extracted 3D model (from tools/extract_unity3d.py)
## in a grid on top of it, so the whole art + model pipeline can be eyeballed
## in one place. Not game logic -- just "does everything actually render."
##
## @tool so this also populates when you just open main.tscn in the editor,
## not only when you press Play -- the scene has no saved child nodes (they're
## all built here, without an owner, so they never get baked into the .tscn).

const MAP_TEXTURE_PATH := "res://assets/images/Map/TheMap.jpg"
const MODEL_MANIFEST_PATH := "res://assets/data/_model_manifest.csv"

const GRID_SPACING := 3.5
const GRID_MARGIN := 5.0
const MAP_ASPECT := 8000.0 / 4034.0  # TheMap.jpg is 8000x4034
## Source meshes vary wildly in native scale (hero standees ~5 units across,
## Garrison/Tower pieces ~1-2), so every model is normalized to roughly this
## footprint (its largest XZ extent) for a consistent, visible showcase grid.
const TARGET_FOOTPRINT := 2.4


func _ready() -> void:
	if has_node("Standees"):
		return  # already built (e.g. the scene was reopened in the editor)

	var primary_paths := _load_model_paths()
	primary_paths.sort()

	var columns := int(ceil(sqrt(primary_paths.size() * 2.0)))
	columns = maxi(columns, 1)
	var rows := int(ceil(float(primary_paths.size()) / columns))

	var grid_width := columns * GRID_SPACING
	var grid_depth := rows * GRID_SPACING

	_setup_environment()
	_setup_map(grid_width + GRID_MARGIN * 2.0, grid_depth + GRID_MARGIN * 2.0)
	_setup_camera(grid_width, grid_depth)
	_place_models(primary_paths, columns, rows)


func _load_model_paths() -> Array[String]:
	var paths: Array[String] = []
	for row in CsvParser.parse_file_as_dicts(MODEL_MANIFEST_PATH):
		var p: String = row.get("primary_obj", "")
		if p != "":
			paths.append(p)
	return paths


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = Sky.new()
	env.sky.sky_material = ProceduralSkyMaterial.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8

	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _setup_map(min_width: float, min_depth: float) -> void:
	# Keep TheMap.jpg's real aspect ratio while still covering the grid+margin.
	var width := min_width
	var depth := width / MAP_ASPECT
	if depth < min_depth:
		depth = min_depth
		width = depth * MAP_ASPECT

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(width, depth)

	var material := StandardMaterial3D.new()
	material.albedo_texture = load(MAP_TEXTURE_PATH)
	material.roughness = 1.0

	var map_instance := MeshInstance3D.new()
	map_instance.name = "MapBoard"
	map_instance.mesh = mesh
	map_instance.set_surface_override_material(0, material)
	add_child(map_instance)


func _setup_camera(grid_width: float, grid_depth: float) -> void:
	var camera := Camera3D.new()
	camera.name = "MainCamera"
	var span := maxf(grid_width, grid_depth)
	# Steeper overhead angle than a 45-degree default so the flat standees
	# (textured on their +Y face) stay legible instead of foreshortening away.
	camera.position = Vector3(0.0, span * 1.1, span * 0.45)
	camera.far = span * 6.0
	add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)
	camera.current = true


func _place_models(paths: Array[String], columns: int, rows: int) -> void:
	var container := Node3D.new()
	container.name = "Standees"
	add_child(container)

	var start_x := -(columns - 1) * GRID_SPACING * 0.5
	var start_z := -(rows - 1) * GRID_SPACING * 0.5

	var placed := 0
	for i in paths.size():
		var path := paths[i]
		var mesh: Mesh = load(path)
		if mesh == null:
			push_warning("main.gd: could not load mesh '%s'" % path)
			continue

		var inst := MeshInstance3D.new()
		inst.name = path.get_file().get_basename()
		inst.mesh = mesh

		var aabb := mesh.get_aabb()
		var footprint := maxf(aabb.size.x, aabb.size.z)
		if footprint > 0.001:
			var s := TARGET_FOOTPRINT / footprint
			inst.scale = Vector3(s, s, s)

		var col := i % columns
		var row := i / columns
		inst.position = Vector3(start_x + col * GRID_SPACING, 0.02, start_z + row * GRID_SPACING)

		container.add_child(inst)
		placed += 1

	print("main.gd: placed %d/%d models in a %dx%d grid" % [placed, paths.size(), columns, rows])
