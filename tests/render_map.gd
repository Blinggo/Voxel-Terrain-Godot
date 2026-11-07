extends SceneTree

## Renders a hillshaded top-down map of the surface, for judging geography.
##
## Usage:
##   godot --headless --path . -s res://tests/render_map.gd -- \
##       --out=/tmp/map.png --seed=1337 --size=1024
##
## Why this exists: a 3D screenshot shows one camera angle of a few hundred
## voxels, which is a bad instrument for tuning fields. A top-down map of a
## square kilometre shows whether continents, coastlines, shelves and mountain
## belts actually have the shapes they are supposed to - that is what the M1
## field tuning was judged on. It is a tool, not a test: it asserts nothing and
## exits 0.
##
## The colour ramp is diagnostic, not the game's palette: water is shaded by
## depth, sand near the waterline, grass on lowland, rock on high ground, white on
## the highest. Nothing here feeds back into generation.

const DEFAULT_OUT := "/tmp/terrain_map.png"
const DEFAULT_SIZE := 512


func _init() -> void:
	var out := DEFAULT_OUT
	var seed_value := 1337
	var size := DEFAULT_SIZE

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg.begins_with("--seed="):
			seed_value = int(arg.get_slice("=", 1))
		elif arg.begins_with("--size="):
			size = maxi(int(arg.get_slice("=", 1)), 32)

	var config := WorldConfig.new()
	config.world_seed = seed_value
	var surface := GeographicSurface.new(config)
	if not surface.is_valid():
		push_error("render_map: the generation pipeline failed to build.")
		quit(1)
		return

	var sea_level := config.sea_level
	var ocean_depth := maxf(config.ocean_depth, 1.0)
	var limit := size / 2
	var heights := surface.sample_block_heights(Vector2i(-limit, -limit), Vector2i(size, size))

	var image := Image.create(size, size, false, Image.FORMAT_RGB8)
	for j in range(size):
		for i in range(size):
			var height: float = heights[j * size + i]

			# Hillshade from the height gradient, light from the north-west.
			var dx: float = heights[j * size + mini(i + 1, size - 1)] - height
			var dz: float = heights[mini(j + 1, size - 1) * size + i] - height
			var shade := clampf(1.0 - (dx + dz) * 0.25, 0.45, 1.35)

			var color: Color
			if height < sea_level:
				var depth := clampf((sea_level - height) / ocean_depth, 0.0, 1.0)
				color = Color(0.08, 0.22, 0.45).lerp(Color(0.35, 0.65, 0.85), 1.0 - depth)
			elif height < sea_level + 2.0:
				color = Color(0.80, 0.75, 0.55)
			elif height < sea_level + 12.0:
				color = Color(0.32, 0.60, 0.28)
			elif height < sea_level + 26.0:
				color = Color(0.25, 0.48, 0.22)
			elif height < sea_level + 40.0:
				color = Color(0.45, 0.42, 0.38)
			else:
				color = Color(0.92, 0.92, 0.95)

			image.set_pixel(i, j, Color(color.r * shade, color.g * shade, color.b * shade))

	var error := image.save_png(out)
	if error != OK:
		push_error("render_map: save_png failed (%d) for %s" % [error, out])
		quit(1)
		return

	print("MAP_OK %s %dx%d seed=%d" % [out, size, size, seed_value])
	quit(0)
