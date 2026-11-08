extends SceneTree

func _initialize() -> void:
	var best := 0
	for seed_value in [1337,90210,4242]:
		var cfg := WorldConfig.new()
		cfg.world_seed = seed_value
		var surface := GeographicSurface.new(cfg)
		var drainage := surface.get_drainage()
		var seen: Dictionary = {}
		for z in range(-1024,1025,128):
			for x in range(-1024,1025,128):
				var tile := drainage.tile_at(Vector2i(x,z))
				for lake in tile.lakes:
					if not seen.has(lake.id):
						seen[lake.id] = true
						if lake.cells.size() > best:
							best = lake.cells.size()
							print("BEST_LAKE seed=",seed_value," center=",lake.center," count=",best," level=",lake.level)
		print("SEED_SURVEY ",seed_value," lakes=",seen.size()," ",drainage.stats())
	quit()
