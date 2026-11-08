extends SceneTree

func _initialize() -> void:
	for enabled in [false,true]:
		var cfg := WorldConfig.new()
		cfg.hydrology_enabled = enabled
		var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
		var surface := GeographicSurface.new(cfg)
		var cold := Time.get_ticks_usec()
		for z in range(8):
			for x in range(8):
				surface.sample_block_heights(Vector2i(192+x*16,-640+z*16),Vector2i(16,16))
		print("M4_PERF hydrology=",enabled," cold64_ms=",(Time.get_ticks_usec()-cold)/1000.0)
		for smooth_mode in [false,true]:
			var adapter: VoxelGeneratorScript
			if smooth_mode:
				var smooth := TerrainSmoothGenerator.new()
				smooth.configure(surface)
				adapter = smooth
			else:
				var blocky := TerrainBlockGenerator.new()
				blocky.configure(surface,BlockPalette.new())
				adapter = blocky
			var buffer := VoxelBuffer.new()
			buffer.create(16,16,16)
			buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF,VoxelBuffer.DEPTH_32_BIT)
			buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE,VoxelBuffer.DEPTH_16_BIT)
			var started := Time.get_ticks_usec()
			for repeat in range(3):
				for z in range(8):
					for x in range(8):
						# Reset air for the blocky adapter's untouched-above-surface contract.
						buffer.fill(0,VoxelBuffer.CHANNEL_TYPE)
						adapter._generate_block(buffer,Vector3i(192+x*16,16,-640+z*16),0)
			print("M4_PERF hydrology=",enabled," smooth=",smooth_mode," warm_us_per_block=",(Time.get_ticks_usec()-started)/192.0)
		var query_start := Time.get_ticks_usec()
		for i in range(1000):
			surface.get_water_at(256,-544)
		print("M4_PERF hydrology=",enabled," water_query_us=",(Time.get_ticks_usec()-query_start)/1000.0," static_delta_MB=",(Performance.get_monitor(Performance.MEMORY_STATIC)-memory_before)/1048576.0)
		if enabled:
			var network := surface.get_drainage()
			for phase in range(3):
				for i in range(150):
					network.tile_at(Vector2i((phase*150+i)*128,0))
				print("M4_TRAVEL phase=",phase," static_MB=",Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0," stats=",network.stats())
	quit()
