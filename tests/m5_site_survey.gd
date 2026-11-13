extends SceneTree
func _initialize() -> void:
	for seed_value in [1337,90210,4242]:
		var cfg := WorldConfig.new()
		cfg.world_seed = seed_value
		cfg.density_mode = 1
		cfg.hydrology_enabled = false
		var surface := GeographicSurface.new(cfg)
		var profiles := LandformProfiles.new()
		var best: Dictionary = {}
		for z in range(-1600,1025,64):
			for x in range(-1024,1025,64):
				var land := surface.get_field_at(&"landmass",x,z)
				if land < 0.15: continue
				var weights := profiles.weights(land,surface.get_field_at(&"mountainness",x,z),surface.get_field_at(&"hills",x,z),surface.get_field_at(&"plateaus",x,z),surface.get_field_at(&"valleys",x,z),surface.get_field_at(&"elevation",x,z))
				for i in range(weights.size()):
					if not best.has(i) or weights[i] > best[i].weight:
						best[i] = {"weight":weights[i],"point":Vector2i(x,z),"height":surface.get_surface_height(x,z)}
		print("SURVEY seed=",seed_value," ",best)
	quit()
