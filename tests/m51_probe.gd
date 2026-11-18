extends SceneTree
func _initialize() -> void:
	for enabled in [false,true]:
		var cfg := WorldConfig.new()
		cfg.density_mode = 1
		cfg.mountain_morphology_enabled = enabled
		cfg.hydrology_enabled = false
		var surface := GeographicSurface.new(cfg)
		var maximum := -INF
		var best := Vector2i.ZERO
		var heights: Array[float] = []
		var start := Time.get_ticks_usec()
		for z in range(-1728,-1215,8):
			for x in range(-256,257,8):
				var h := surface.get_surface_height(x,z)
				heights.append(h)
				if h > maximum:
					maximum = h
					best = Vector2i(x,z)
		heights.sort()
		var width := 0
		for z in range(best.y-64,best.y+65,4):
			for x in range(best.x-64,best.x+65,4):
				if surface.get_surface_height(x,z) >= maximum*0.9: width += 1
		print("M51_SURVEY enabled=",enabled," max=",maximum," best=",best," p95=",heights[int(heights.size()*0.95)]," summit90_cells16sq=",width," ms=",(Time.get_ticks_usec()-start)/1000.0)
	quit()
