extends RefCounted

static func run(report) -> void:
	var legacy_cfg := WorldConfig.new()
	var legacy := TerrainDensity.new(GeographicSurface.new(legacy_cfg))
	var h := legacy.surface.get_surface_height(128,128)
	report.check("legacy zero surface",absf(legacy.sample_density(Vector3(128,h,128))) < 0.00001)
	report.check("negative inside / positive outside",legacy.sample_density(Vector3(128,h-3,128)) < 0 and legacy.sample_density(Vector3(128,h+3,128)) > 0)
	var cfg := legacy_cfg.duplicate_config()
	cfg.density_mode = 1
	var density := TerrainDensity.new(GeographicSurface.new(cfg))
	var origin := Vector3i(-128,80,-1472)
	var size := Vector3i(16,16,16)
	var values := density.sample_block(origin,size)
	report.check("repeat density deterministic",values == density.sample_block(origin,size))
	var clone := TerrainDensity.new(GeographicSurface.new(cfg))
	report.check("reconstruction deterministic",values == clone.sample_block(origin,size))
	var point_matches := true
	for z in range(0,16,5):
		for x in range(0,16,5):
			for y in range(0,16,5):
				point_matches = point_matches and absf(density.sample_density(Vector3(origin+Vector3i(x,y,z)))-values[(z*16+x)*16+y]) < 0.0001
	report.check("point/block same field",point_matches)
	var wide := density.sample_block(origin,Vector3i(32,16,16))
	var right := density.sample_block(origin+Vector3i(16,0,0),size)
	var partition := true
	for z in range(16):
		for x in range(32):
			for y in range(16):
				var expected := values[(z*16+x)*16+y] if x < 16 else right[(z*16+x-16)*16+y]
				partition = partition and absf(wide[(z*32+x)*16+y]-expected) < 0.0001
	report.check("chunk partition and seam samples agree",partition)
	var continuous := true
	for x in [-128,-96,-1,0,128]:
		var p := Vector3(x,60,-1472)
		continuous = continuous and absf(density.sample_density(p-Vector3(0.0001,0,0))-density.sample_density(p+Vector3(0.0001,0,0))) < 0.02
	report.check("continuous across grid and negative-coordinate boundaries",continuous)
	cfg.density_structure_amplitude = 0
	cfg.world_seed = 888
	report.check("caller config mutation cannot change live density",values == density.sample_block(origin,size))
	var changed := TerrainDensity.new(GeographicSurface.new(cfg))
	report.check("different seed changes density",values != changed.sample_block(origin,size))
	var profile := LandformProfile.make(&"plains",0,0.2,0,0,0,0,0)
	cfg.landform_profiles = [profile]
	var snapshot := cfg.duplicate_config()
	profile.relief = 99
	report.check("nested profile snapshot is independent",snapshot.landform_profiles[0].relief == 0.2)
	var catalog := LandformProfiles.new()
	report.check("ten distinct configurable profiles",catalog.profiles.size() == 10 and LandformProfiles.IDS.size() == 10)
	var normalized := true
	var soft := true
	var previous := catalog.weights(0.7,0,0.3,0,0.2,0.4)
	for j in range(101):
		var w := catalog.weights(0.7,j/100.0,0.3,0,0.2,0.4)
		var total := 0.0
		for k in range(10):
			total += w[k]
			normalized = normalized and w[k] >= 0
			soft = soft and absf(w[k]-previous[k]) < 0.08
		normalized = normalized and absf(total-1) < 0.00001
		previous = w
	report.check("profile weights partition unity",normalized)
	report.check("foothill-to-range blending is continuous",soft)
	report.check("relative plains/hills/alpine relief",catalog.profiles[0].relief < catalog.profiles[1].relief and catalog.profiles[1].relief < catalog.profiles[5].relief)
	report.check("plateau interior retains constant elevation",is_equal_approx(catalog.shape(60,30,0.8,0.2,0.4,1,0,0.4),catalog.shape(60,30,0.8,0.8,0.1,1,0.5,-0.4)))
	report.check("basin profile is depressed and low-relief",catalog.profiles[7].broad_elevation < 0 and catalog.profiles[7].relief < catalog.profiles[4].relief)
	report.check("coast density effects disabled",catalog.density_controls(-0.2,0.7,0.5,0,0.2,0.3) == Vector3.ZERO)
	var plain_legacy := legacy.surface.get_surface_height(128,128)
	var plain_hybrid := density.surface.get_surface_height(128,128)
	report.check("profile composition flattens sampled plain",plain_hybrid < plain_legacy)
	report.check("profile composition raises sampled alpine range",density.surface.get_surface_height(-64,-1472) > legacy.surface.get_surface_height(-64,-1472)+20)
	_test_noise(report)
	var scan := density.sample_block(Vector3i(-128,0,-1536),Vector3i(128,160,128))
	var overhangs := 0
	for column in range(128*128):
		var crossings := 0
		for y in range(1,160):
			if (scan[column*160+y] > 0) != (scan[column*160+y-1] > 0): crossings += 1
		if crossings >= 3: overhangs += 1
	report.check("genuine non-heightmap geometry: multiple vertical solid intervals",overhangs > 0,"%d columns" % overhangs)
	var blocky := TerrainBlockGenerator.new()
	blocky.configure(density.surface,BlockPalette.new(),density)
	var smooth := TerrainSmoothGenerator.new()
	smooth.configure(density.surface,density)
	report.check("both adapters share the exact field instance",blocky.get_density() == smooth.get_density())
	var block := VoxelBuffer.new()
	block.create(16,16,16)
	block.set_channel_depth(VoxelBuffer.CHANNEL_TYPE,VoxelBuffer.DEPTH_16_BIT)
	block.set_channel_depth(VoxelBuffer.CHANNEL_SDF,VoxelBuffer.DEPTH_32_BIT)
	blocky._generate_block(block,origin,0)
	smooth._generate_block(block,origin,0)
	var sdf_ok := true
	var materials_ok := true
	var materials := density.material_block(origin,size,BlockPalette.new())
	for z in range(16):
		for x in range(16):
			for y in range(16):
				var i := (z*16+x)*16+y
				sdf_ok = sdf_ok and absf(block.get_voxel_f(x,y,z,VoxelBuffer.CHANNEL_SDF)-clampf(values[i],-TerrainSmoothGenerator.SDF_LIMIT,TerrainSmoothGenerator.SDF_LIMIT)) < 0.0001
				materials_ok = materials_ok and block.get_voxel(x,y,z,VoxelBuffer.CHANNEL_TYPE) == materials[i] and ((materials[i] != 0) == (values[i] <= 0))
	var interval := density._density_interval(origin,size)
	var bounded := true
	for value in values: bounded = bounded and value >= interval.x-0.0001 and value <= interval.y+0.0001
	report.check("uniform-write interval conservatively contains dense samples",bounded)
	for height in [-400,400]:
		var far_origin := Vector3i(0,height,0)
		blocky._generate_block(block,far_origin,0)
		smooth._generate_block(block,far_origin,0)
		var expected_material := BlockPalette.AIR if height > 0 else BlockPalette.STONE
		var expected_sdf := TerrainSmoothGenerator.SDF_LIMIT if height > 0 else -TerrainSmoothGenerator.SDF_LIMIT
		report.check("uniform encoding at y="+str(height),block.get_voxel(0,0,0,VoxelBuffer.CHANNEL_TYPE) == expected_material and block.get_voxel_f(0,0,0,VoxelBuffer.CHANNEL_SDF) == expected_sdf)
	report.check("smooth SDF channel preserves shared sign/value",sdf_ok)
	report.check("blocky material channel agrees with density solidity",materials_ok)
	var native_buffer := VoxelBuffer.new()
	native_buffer.create(19,19,19)
	native_buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF,VoxelBuffer.DEPTH_32_BIT)
	var native_origin := Vector3i(-112,floori(density.surface.get_surface_height(-112,-1472))-8,-1472)
	smooth._generate_block(native_buffer,native_origin,0)
	var mesher := VoxelMesherTransvoxel.new()
	mesher.transitions_enabled = false
	var mesh: ArrayMesh = mesher.build_mesh(native_buffer,[],{})
	var native_ok := mesh != null and mesh.get_surface_count() > 0
	if native_ok:
		var normals: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		native_ok = normals.size() > 0
		for normal in normals: native_ok = native_ok and normal.is_finite() and absf(normal.length()-1) < 0.05
	report.check("native hybrid mesh has finite normalized normals",native_ok)
	var workers: Array[Thread] = []
	for i in range(4):
		var worker := Thread.new()
		worker.start(func(): return density.sample_block(origin,size))
		workers.append(worker)
	var threaded := true
	for worker in workers: threaded = threaded and worker.wait_to_finish() == values
	report.check("four-worker density identity",threaded)
	density.clear_cache()
	report.check("cache eviction/reconstruction preserves field",density.sample_block(origin,size) == values)
	_test_hydrology(report,density)
	var cheap_cfg := WorldConfig.new()
	cheap_cfg.hydrology_enabled = false
	cheap_cfg.density_mode = 1
	var cached := TerrainDensity.new(GeographicSurface.new(cheap_cfg))
	for i in range(270): cached._column_controls(Vector2i(i*16,0),Vector2i(16,16))
	report.check("density 2D cache bounded",cached.cache_stats().columns == TerrainDensity.CONTROLS_CAPACITY)

static func _test_noise(report) -> void:
	var cfg := WorldConfig.new()
	cfg.density_mode = 1
	cfg.hydrology_enabled = false
	cfg.density_geological_amplitude = 0
	cfg.density_structure_amplitude = 0
	cfg.density_roughness_amplitude = 0
	var zero := TerrainDensity.new(GeographicSurface.new(cfg))
	report.check("all bands disabled exactly y-H",zero._evaluate(Vector3(12,94,30),100,Vector3.ONE) == -6)
	for band in ["geological","structure","roughness"]:
		var one := cfg.duplicate_config()
		one.set("density_"+band+"_amplitude",10.0)
		var a := TerrainDensity.new(GeographicSurface.new(one))
		var higher := one.duplicate_config()
		higher.set("density_"+band+"_amplitude",20.0)
		var b := TerrainDensity.new(GeographicSurface.new(higher))
		var frequency := one.duplicate_config()
		frequency.set("density_"+band+"_frequency",0.1)
		var c := TerrainDensity.new(GeographicSurface.new(frequency))
		var active := false
		var frequency_changes := false
		var scales := true
		for x in range(0,100,5):
			var p := Vector3(x,94,30)
			var va := a._evaluate(p,100,Vector3.ONE)+6
			var vb := b._evaluate(p,100,Vector3.ONE)+6
			var vc := c._evaluate(p,100,Vector3.ONE)+6
			active = active or absf(va) > 0.0001
			frequency_changes = frequency_changes or absf(va-vc) > 0.0001
			scales = scales and absf(vb-2*va) < 0.0001 and absf(va) <= 10
		report.check(band+" toggle/amplitude/bounds",active and scales)
		report.check(band+" frequency affects its field",frequency_changes)
	report.check("finite band has unmodified deep solid",zero._evaluate(Vector3(0,-500,0),100,Vector3.ONE) == -600)

static func _test_hydrology(report,density: TerrainDensity) -> void:
	var protected := true
	var reaches := 0
	var carved := false
	for z in range(-640,-255,128):
		for x in range(128,513,128):
			var tile := density.surface.get_drainage().tile_at(Vector2i(x,z))
			for edge in tile.segments:
				var p := Vector2i((edge.a+edge.b)*0.5)
				var q := density.surface.get_water_at(p.x,p.y)
				if q.kind == "river" or q.kind == "lake":
					reaches += 1
					var h := density.surface.get_surface_height(p.x,p.y)
					protected = protected and absf(density.sample_density(Vector3(p.x,h-2,p.y))+2) < 0.0001
					carved = carved or h < density.surface.get_unmodified_height(p.x,p.y)-0.5
	report.check("hybrid hydrology still carves final base surface",carved and reaches > 0)
	report.check("volumetric modifiers do not open sampled water beds",protected and reaches > 0,"%d wet reaches" % reaches)

static func run_scene_checks(report,tree: SceneTree) -> void:
	await tree.process_frame
	for path in ["res://scenes/main.tscn","res://scenes/smooth_terrain.tscn"]:
		var scene = load(path).instantiate()
		tree.root.add_child(scene)
		var world: VoxelWorld = scene.world
		report.check(path+" explicit density ownership",world.get_density() == world.get_generator().get_density() and world.config.density_mode == 1)
		scene.camera.focus_on(Vector3(120,60,120))
		var pose: Transform3D = scene.camera.global_transform
		var seed_value: int = world.config.world_seed
		scene._toggle_density_mode()
		report.check(path+" mode toggle preserves seed/camera",world.config.density_mode == 0 and world.config.world_seed == seed_value and scene.camera.global_transform.is_equal_approx(pose))
		scene.camera.set_fly_mode(true)
		scene.camera.global_position += Vector3(8,12,-9)
		var fly_pose: Transform3D = scene.camera.global_transform
		scene._toggle_density_mode()
		report.check(path+" mode toggle preserves free-flight pose",world.config.density_mode == 1 and scene.camera.fly_mode and scene.camera.global_transform.is_equal_approx(fly_pose))
		scene.queue_free()
		await tree.process_frame
		await tree.process_frame
