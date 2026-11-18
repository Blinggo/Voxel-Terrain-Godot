extends SceneTree
func _initialize() -> void:
	var cfg := WorldConfig.new()
	cfg.density_mode = 1
	cfg.mountain_morphology_enabled = true
	cfg.hydrology_enabled = false
	cfg.mountain_profiles = [load("res://resources/mountains/massif.tres")]
	var surface := GeographicSurface.new(cfg)
	for x in range(-80,81,8):
		var row := [x]
		for field in [&"landmass",&"mountainness",&"tectonics",&"plateaus",&"valleys",&"surface"]: row.append(surface.get_field_at(field,x,-1360))
		print(row)
	quit()
