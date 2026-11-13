extends SceneTree
func _initialize() -> void:
	var cfg := WorldConfig.new()
	cfg.density_mode = 1
	var surface := GeographicSurface.new(cfg)
	var density := TerrainDensity.new(surface)
	var origin := Vector2i(-96,-1472)
	var size := Vector2i(16,16)
	var start := Time.get_ticks_usec()
	var base := surface.sample_unmodified_heights(origin,size)
	print("COMPONENT first_base_16sq_us=",Time.get_ticks_usec()-start)
	start = Time.get_ticks_usec()
	surface.sample_block_heights(origin,size)
	print("COMPONENT first_hydro_16sq_us=",Time.get_ticks_usec()-start)
	start = Time.get_ticks_usec()
	for i in range(100): surface.sample_unmodified_heights(origin,size)
	print("COMPONENT warm_base_16sq_us=",(Time.get_ticks_usec()-start)/100.0)
	start = Time.get_ticks_usec()
	for i in range(100): surface.sample_block_heights(origin,size)
	print("COMPONENT warm_carved_cached_16sq_us=",(Time.get_ticks_usec()-start)/100.0)
	var profiles := LandformProfiles.new()
	start = Time.get_ticks_usec()
	for i in range(1000): profiles.shape(80,30,0.7,0.6,0.3,0.1,0.3,0.5)
	print("COMPONENT profile_blend_per_node_us=",(Time.get_ticks_usec()-start)/1000.0)
	start = Time.get_ticks_usec()
	density._column_controls(origin,size)
	print("COMPONENT uncached_controls_16sq_us=",Time.get_ticks_usec()-start)
	start = Time.get_ticks_usec()
	for i in range(100): density._column_controls(origin,size)
	print("COMPONENT cached_controls_16sq_us=",(Time.get_ticks_usec()-start)/100.0)
	for band in ["none","geological","structure","roughness","all","warp"]:
		var measured := cfg.duplicate_config()
		measured.hydrology_enabled = false
		measured.density_geological_amplitude = 2 if band in ["geological","all","warp"] else 0
		measured.density_structure_amplitude = 14 if band in ["structure","all","warp"] else 0
		measured.density_roughness_amplitude = 0.8 if band in ["roughness","all","warp"] else 0
		measured.density_warp_amplitude = 2 if band == "warp" else 0
		var field := TerrainDensity.new(GeographicSurface.new(measured))
		var checksum := 0.0
		start = Time.get_ticks_usec()
		for i in range(20000): checksum += field._evaluate(Vector3(i%100,94,30),100,Vector3.ONE)
		print("COMPONENT evaluate_band=",band," us_per_sample=",(Time.get_ticks_usec()-start)/20000.0," checksum=",checksum)
	print("COMPONENT baseline_checksum=",base[0]," density_cache=",density.cache_stats())
	quit()
