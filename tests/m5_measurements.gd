extends SceneTree

func _initialize() -> void:
	for mode in [0,1]:
		var cfg := WorldConfig.new()
		cfg.density_mode = mode
		var surface := GeographicSurface.new(cfg)
		var density := TerrainDensity.new(surface)
		var origin := Vector3i(-96,64,-1472)
		var size := Vector3i(16,16,16)
		var start := Time.get_ticks_usec()
		density.sample_block(origin,size)
		print("M5_PERF mode=",mode," cold_density_ms=",(Time.get_ticks_usec()-start)/1000.0)
		start = Time.get_ticks_usec()
		for i in range(100):
			density.sample_block(origin,size)
		print("M5_PERF mode=",mode," warm_density_us=",(Time.get_ticks_usec()-start)/100.0)
		var blocky := TerrainBlockGenerator.new()
		blocky.configure(surface,BlockPalette.new(),density)
		var smooth := TerrainSmoothGenerator.new()
		smooth.configure(surface,density)
		var buffer := VoxelBuffer.new()
		buffer.create(16,16,16)
		buffer.set_channel_depth(VoxelBuffer.CHANNEL_TYPE,VoxelBuffer.DEPTH_16_BIT)
		buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF,VoxelBuffer.DEPTH_32_BIT)
		for adapter in [blocky,smooth]:
			start = Time.get_ticks_usec()
			for i in range(50):
				adapter._generate_block(buffer,origin,0)
			print("M5_ADAPTER mode=",mode," smooth=",adapter is TerrainSmoothGenerator," us_per_block=",(Time.get_ticks_usec()-start)/50.0)
	quit()
