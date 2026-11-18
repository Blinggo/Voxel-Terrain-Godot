extends SceneTree
func _initialize() -> void:
	for enabled in [false,true]:
		var cfg := WorldConfig.new()
		cfg.density_mode = 1
		cfg.mountain_morphology_enabled = enabled
		var surface := GeographicSurface.new(cfg)
		var seen: Dictionary = {}
		for z in range(-1792,-767,128):
			for x in range(-512,513,128):
				for lake in surface.get_drainage().tile_at(Vector2i(x,z)).lakes:
					if seen.has(lake.id): continue
					seen[lake.id] = true
					if lake.cells.size() > 15:
						print("M51_LAKE enabled=",enabled," ",lake.id," center=",lake.center," level=",lake.level," cells=",lake.cells.size())
						if lake.id == "lake:1:-46":
							for cell in lake.cells:
								var q := surface.get_water_at(cell.x*8,cell.y*8)
								if q.kind == "lake":
									print("LAKE_QUERY ",cell*8," ",q)
									break
		print("LAKE_INVENTORY enabled=",enabled," count=",seen.size())
	quit()
