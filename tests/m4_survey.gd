extends SceneTree

func _initialize() -> void:
	var cfg := WorldConfig.new()
	var surface := GeographicSurface.new(cfg)
	var network := surface.get_drainage()
	for z in range(-512, 513, 128):
		for x in range(-512, 513, 128):
			var start := Time.get_ticks_usec()
			var tile := network.tile_at(Vector2i(x,z))
			if not tile.segments.is_empty() or not tile.lakes.is_empty():
				print("HYDRO_TILE ", x, ",", z, " edges=", tile.segments.size(), " lakes=", tile.lakes.size(), " ms=", (Time.get_ticks_usec()-start)/1000.0)
				if not tile.lakes.is_empty():
					print("LAKE ", tile.lakes[0].center, " level=", tile.lakes[0].level)
	print("HYDRO_STATS ", network.stats())
	quit()
