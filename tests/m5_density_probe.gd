extends SceneTree

func _initialize() -> void:
	var cfg := WorldConfig.new()
	cfg.density_mode = 1
	var surface := GeographicSurface.new(cfg)
	var density := TerrainDensity.new(surface)
	var origin := Vector3i(-128,0,-1536)
	var size := Vector3i(128,160,128)
	var start := Time.get_ticks_usec()
	var values := density.sample_block(origin,size)
	var overhangs := 0
	var first := Vector2i.ZERO
	var maximum := 0
	for z in range(size.z):
		for x in range(size.x):
			var transitions := 0
			for y in range(1,size.y):
				var index := (z*size.x+x)*size.y+y
				if (values[index] > 0) != (values[index-1] > 0):
					transitions += 1
			if transitions >= 3:
				overhangs += 1
				first = Vector2i(origin.x+x,origin.z+z)
			maximum = maxi(maximum,transitions)
	print("M5 VOLUME scan_ms=",(Time.get_ticks_usec()-start)/1000.0," columns_with_multiple_surfaces=",overhangs," max_crossings=",maximum," example=",first)
	quit()
