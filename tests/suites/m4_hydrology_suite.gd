extends RefCounted

static func run(report) -> void:
	var cfg := WorldConfig.new()
	var a := GeographicSurface.new(cfg)
	var b := GeographicSurface.new(cfg)
	var other_cfg := cfg.duplicate_config()
	other_cfg.world_seed = 90210
	var other := GeographicSurface.new(other_cfg)
	var na := a.get_drainage()
	var nb := b.get_drainage()
	var tiles: Array[Vector2i] = []
	for z in range(-512, 513, 128):
		for x in range(-512, 513, 128):
			tiles.append(Vector2i(x,z))
	var signatures: Dictionary = {}
	var segments: Dictionary = {}
	var lakes: Dictionary = {}
	var started := Time.get_ticks_usec()
	for p in tiles:
		var tile := na.tile_at(p)
		signatures[p] = _signature(tile)
		for edge in tile.segments:
			segments[str(edge.a)+str(edge.b)] = edge
		for lake in tile.lakes:
			lakes[lake.id] = lake
	print("M4 cold survey 81 tiles ms=", (Time.get_ticks_usec()-started)/1000.0, " stats=",na.stats())
	var same := true
	tiles.reverse()
	for p in tiles:
		same = same and signatures[p] == _signature(nb.tile_at(p))
	report.check("network reconstruction is identical in reverse tile order", same)
	var divergence := 0
	var active := 0
	for p in tiles:
		var candidate := _signature(other.get_drainage().tile_at(p))
		if not candidate.is_empty() or not String(signatures[p]).is_empty():
			active += 1
			if signatures[p] != candidate:
				divergence += 1
	report.check("different seeds give different active drainage layouts", active > 10 and float(divergence)/float(active) > 0.75, "%d / %d active tiles" % [divergence,active])
	report.check("survey contains river reaches", segments.size() > 20, "%d chord segments" % segments.size())
	report.check("survey contains enclosed lakes", lakes.size() >= 2, "%d basins" % lakes.size())
	var downhill := true
	var accumulation := true
	var joined := false
	var waterfalls := 0
	var waterfall_valid := true
	var ocean := false
	var lake_ends := false
	var carving := false
	for edge in segments.values():
		downhill = downhill and float(edge.ya) >= float(edge.yb) - 0.0001
		accumulation = accumulation and float(edge.flow_b) >= float(edge.flow_a)
		joined = joined or float(edge.flow_b) >= 2.0
		ocean = ocean or edge.body == "ocean"
		lake_ends = lake_ends or String(edge.body).begins_with("lake:")
		var mid: Vector2 = (edge.a + edge.b)*0.5
		var p := Vector2i(roundi(mid.x),roundi(mid.y))
		carving = carving or a.get_surface_height(p.x,p.y) < a.get_unmodified_height(p.x,p.y)-0.5
		if edge.waterfall:
			waterfalls += 1
			waterfall_valid = waterfall_valid and float(edge.drop) >= 8.0 and float(edge.ya) >= float(edge.yb)
	report.check("all sampled river water profiles are nonascending", downhill)
	report.check("source accumulation is nondecreasing downstream", accumulation)
	report.check("multiple source contributions merge into shared reaches", joined)
	report.check("river networks include ocean terminals", ocean)
	report.check("river networks include basin-lake terminals", lake_ends)
	report.check("hydrology carves the actual geographical surface", carving)
	report.check("waterfall candidates have real descending reach drops", waterfalls > 0 and waterfall_valid, "%d waterfall chords" % waterfalls)
	var lake_queries := 0
	var stable := true
	var depressed := true
	for lake in lakes.values():
		depressed = depressed and float(lake.level) > float(lake.bottom)
		print("M4 LAKE ",lake.id," samples=",lake.cells.size()," level=",lake.level)
		var level: float = lake.level
		for cell in lake.cells:
			var p: Vector2i = cell * DrainageNetwork.LAKE_STEP
			var q := a.get_water_at(p.x,p.y)
			if q.body_id == lake.id:
				lake_queries += 1
				stable = stable and absf(float(q.water_height)-level) < 0.0001
	report.check("lakes occupy lower terrain within validated flood components", depressed)
	report.check("queried lake levels are constant per body", stable and lake_queries >= 3)
	var border_equal := true
	var width_equal := true
	for z in range(-400,401,13):
		var p := Vector2i(128,z)
		var base := a.get_unmodified_height(p.x,p.y)
		var left := na.sample(Vector2(p),base,na.tile_at(p-Vector2i(1,0)))
		var right := na.sample(Vector2(p),base,na.tile_at(p))
		border_equal = border_equal and left == right
		width_equal = width_equal and left.z == right.z
	report.check("adjacent hydrology indexes agree exactly on shared boundary", border_equal)
	report.check("river width agrees across regional boundary", width_equal)
	var block := a.sample_block_heights(Vector2i(304,-304),Vector2i(32,32))
	var columns := true
	for z in range(0,32,3):
		for x in range(0,32,3):
			columns = columns and absf(block[z*32+x]-a.get_surface_height(304+x,-304+z)) < 0.0001
	report.check("carved bulk columns equal independent arbitrary samples", columns)
	var disabled := cfg.duplicate_config()
	disabled.hydrology_enabled = false
	var raw := GeographicSurface.new(disabled)
	report.check("disabled hydrology allocates no drainage service", raw.get_drainage() == null)
	report.check_equal("hydrology off reproduces pre-carve height", raw.get_surface_height(320,-288), a.get_unmodified_height(320,-288))
	var routes := na.inspect_routes(Rect2i(-4,-4,9,9))
	var eligible := not routes.is_empty()
	var terminal_ok := not routes.is_empty()
	for route in routes:
		eligible = eligible and float(route.nodes[0].height) >= cfg.sea_level + cfg.hydrology_source_rise
		var end: Dictionary = route.nodes[-1]
		terminal_ok = terminal_ok and (float(end.height) <= cfg.sea_level or (end.receiver == end.cell and route.terminal.has("cells")))
	report.check("accepted river sources are elevated, not uniform plain decoration",eligible)
	report.check("every accepted complete route reaches ocean or enclosed basin",terminal_ok)
	var stats := na.stats()
	report.check("all drainage caches obey explicit capacity limits", int(stats.tiles) <= 32 and int(stats.routes) <= 1024 and int(stats.nodes) <= 8192 and int(stats.lakes) <= 512)
	var p := Vector2i(320,-288)
	var first := a.get_water_at(p.x,p.y)
	for i in range(100):
		a.get_water_at(p.x,p.y)
	report.check_equal("repeat water queries do not change results", a.get_water_at(p.x,p.y), first)
	# M3 ownership regression: releasing a stack must release registry/module cycles.
	var weak: WeakRef = weakref(raw._stack.registry)
	raw = null
	report.check("generation registry is released with its owning surface", weak.get_ref() == null)
	# Same field drives actual blocky and SDF adapter paths.
	var blocky := TerrainBlockGenerator.new()
	blocky.configure(a,BlockPalette.new())
	var smooth := TerrainSmoothGenerator.new()
	smooth.configure(a)
	var h := a.get_surface_height(320,-288)
	var buffer := VoxelBuffer.new()
	buffer.create(1,8,1)
	buffer.set_channel_depth(VoxelBuffer.CHANNEL_SDF,VoxelBuffer.DEPTH_32_BIT)
	var origin := Vector3i(320,floori(h)-3,-288)
	smooth._generate_block(buffer,origin,0)
	report.check("smooth adapter includes carved height in density", absf(buffer.get_voxel_f(0,0,0,VoxelBuffer.CHANNEL_SDF)-(origin.y-h)) < 0.0001)
	blocky._generate_block(buffer,origin,0)
	report.check("blocky adapter includes same carved height", buffer.get_voxel(0,3,0,VoxelBuffer.CHANNEL_TYPE) == BlockPalette.GRASS and buffer.get_voxel(0,4,0,VoxelBuffer.CHANNEL_TYPE) == BlockPalette.AIR)
	# M3 normal convention: polygonize an actual plane and inspect native normals.
	var plane := VoxelBuffer.new()
	plane.create(19,19,19)
	plane.set_channel_depth(VoxelBuffer.CHANNEL_SDF,VoxelBuffer.DEPTH_32_BIT)
	for z in range(19):
		for x in range(19):
			for y in range(19):
				plane.set_voxel_f(float(y)-8.25,x,y,z,VoxelBuffer.CHANNEL_SDF)
	var mesher := VoxelMesherTransvoxel.new()
	mesher.transitions_enabled = false
	var mesh: ArrayMesh = mesher.build_mesh(plane,[],{})
	var up := mesh != null and mesh.get_surface_count() > 0
	if up:
		var arrays := mesh.surface_get_arrays(0)
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		up = normals.size() > 0
		for normal in normals:
			up = up and normal.y > 0.99
	report.check("M3 smooth negative-inside plane has outward upward normals",up)
	var before_cached := a.sample_block_heights(Vector2i(240,-560),Vector2i(16,16))
	a.set_cache_enabled(false)
	var uncached := a.sample_block_heights(Vector2i(240,-560),Vector2i(16,16))
	report.check_equal("bounded final-column cache does not change carved geometry",before_cached,uncached)
	a.set_cache_enabled(true)
	var threads: Array[Thread] = []
	for i in range(4):
		var thread := Thread.new()
		thread.start(_thread_sample.bind(a))
		threads.append(thread)
	var consistent := true
	for thread in threads:
		var result: PackedFloat32Array = thread.wait_to_finish()
		consistent = consistent and result == before_cached
	report.check("four workers reconstruct the same carved columns",consistent)
	var controls := FlightControls.new()
	var camera := OrbitCamera.new()
	controls.camera = camera
	camera.touch_move = Vector3.ONE
	camera.fly_velocity = Vector3.ONE
	camera.touch_boost = true
	controls._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	report.check("application pause cancels touch movement and boost",camera.touch_move == Vector3.ZERO and camera.fly_velocity == Vector3.ZERO and not camera.touch_boost)
	camera._orbiting = true
	camera._touches[2] = Vector2.ONE
	camera._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	report.check("focus loss clears orbit gesture ownership",not camera._orbiting and camera._touches.is_empty())
	controls.free()
	camera.free()
	print("M4 final cache stats ", na.stats())

static func _signature(tile: Dictionary) -> String:
	var parts: Array[String] = []
	for edge in tile.segments:
		parts.append(str(edge.a)+str(edge.b)+str(edge.wa)+str(edge.wb)+str(edge.ya)+str(edge.yb))
	for lake in tile.lakes:
		parts.append(lake.id+str(lake.level))
	parts.sort()
	return "|".join(parts)


static func _thread_sample(surface: GeographicSurface) -> PackedFloat32Array:
	return surface.sample_block_heights(Vector2i(240,-560),Vector2i(16,16))
