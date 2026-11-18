extends RefCounted

static func _height(p: LandformProfile,d: float,ribs: float = 0.6,detail: float = 0.0,geological: float = 0.4) -> float:
	return MountainMorphology.evaluate_profile(p,MountainMorphology.compile_vertical(p),d,ribs,detail,geological)

static func run(report) -> void:
	var catalog := MountainMorphology.new()
	var p: LandformProfile = catalog.profiles[1].duplicate(true)
	var cases := [
		["mountain_width",0.6,1.2,0.4,1],
		["summit_width",0.18,0.55,0.2,1],
		["summit_sharpness",0.55,1.55,0.1,-1],
		["ridge_width",0.2,0.8,0.25,1],
		["shoulder_width",0.4,1.0,0.5,1],
		["foothill_width",0.8,1.8,1.2,1],
		["mountain_valley_influence",0.0,0.9,0.6,-1],
		["overall_elevation",0.8,1.3,0.2,1],
		["surface_roughness",0.0,0.15,0.4,1],
		["geological_detail",0.0,0.6,0.5,1],
		["mountain_ridge_influence",0.0,0.9,0.0,-1]]
	for c in cases:
		var a: LandformProfile = p.duplicate(true)
		var b: LandformProfile = p.duplicate(true)
		a.set(c[0],c[1]); b.set(c[0],c[2])
		var delta := _height(b,c[3],0.6,0.5)-_height(a,c[3],0.6,0.5)
		report.check("morphology "+c[0]+" has expected geometric effect",delta*float(c[4]) > 0.0001,"delta="+str(delta))
	var narrow_cap: LandformProfile = p.duplicate(true)
	var wide_cap: LandformProfile = p.duplicate(true)
	narrow_cap.summit_width = 0.18
	wide_cap.summit_width = 0.55
	var cap_counts := Vector2i.ZERO
	for i in range(201):
		if _height(narrow_cap,i/200.0,1,0) > p.overall_elevation*0.9: cap_counts.x += 1
		if _height(wide_cap,i/200.0,1,0) > p.overall_elevation*0.9: cap_counts.y += 1
	report.check("summit width expands upper-ten-percent cross-section",cap_counts.y > cap_counts.x*1.5,str(cap_counts))
	var extra: LandformProfile = p.duplicate(true)
	extra.id = &"future_custom"
	extra.overall_elevation = 1.6
	report.check("new resource identity works without module edits",MountainMorphology.new([extra]).evaluate(0,1,0,0.5) > 1.5)
	var cap_invariant := true
	for field in ["mountain_width","summit_width","summit_sharpness","shoulder_width","foothill_width"]:
		var a: LandformProfile = p.duplicate(true)
		a.set(field,float(a.get(field))*1.7)
		cap_invariant = cap_invariant and absf(_height(a,0,1,0)-p.overall_elevation) < 0.00001
	report.check("width/shape changes preserve theoretical summit elevation",cap_invariant)
	var curve := MountainMorphology.compile_vertical(p)
	var previous := -1.0
	var monotone := true
	for i in range(1001):
		var current := MountainMorphology.vertical(curve,i/1000.0)
		monotone = monotone and current > previous
		previous = current
	report.check("vertical profile strictly increasing without shelves",monotone)
	var continuous := true
	for k in p.terrain_y_thresholds:
		if k <= 0 or k >= 1: continue
		var mid := MountainMorphology.vertical(curve,k)
		var left := (mid-MountainMorphology.vertical(curve,k-0.00001))/0.00001
		var right := (MountainMorphology.vertical(curve,k+0.00001)-mid)/0.00001
		continuous = continuous and absf(left-right) < 0.01
	report.check("vertical key derivatives continuous",continuous)
	var edited: LandformProfile = p.duplicate(true)
	edited.terrain_y_positions[2] = 0.75
	report.check("Y-key edits move middle mountain elevation",MountainMorphology.vertical(MountainMorphology.compile_vertical(edited),0.48) > MountainMorphology.vertical(curve,0.48)+0.1)
	var blend_ok := true
	var max_step := 0.0
	var last := catalog.evaluate(0.3,0.6,0.1,0)
	for i in range(1001):
		var w := catalog.weights(i/1000.0)
		var sum := 0.0
		for weight in w: sum += weight
		blend_ok = blend_ok and absf(sum-1) < 0.00001
		var v := catalog.evaluate(0.3,0.6,0.1,i/1000.0)
		max_step = maxf(max_step,absf(v-last))
		last = v
	report.check("normalized profile blend has no hard switches",blend_ok and max_step < 0.01,"max step="+str(max_step))
	var wide: LandformProfile = p.duplicate(true)
	wide.transition_width = 2.0
	var narrow: LandformProfile = p.duplicate(true)
	narrow.transition_width = 0.5
	var blended_a := MountainMorphology.new([narrow,catalog.profiles[4]])
	var blended_b := MountainMorphology.new([wide,catalog.profiles[4]])
	report.check("transition width changes blended geometry",absf(blended_a.evaluate(0.2,0.6,0.1,0.5)-blended_b.evaluate(0.2,0.6,0.1,0.5)) > 0.001)
	var snapshot := MountainMorphology.new([p])
	var before := snapshot.evaluate(0.3,0.6,0.1,0.5)
	p.summit_width = 0.01
	report.check("profile caller mutation cannot affect snapshot",snapshot.evaluate(0.3,0.6,0.1,0.5) == before)
	var styles: Array[float] = []
	for profile in catalog.profiles: styles.append(_height(profile,0.3,0.6,0.3))
	styles.sort()
	report.check("six resource styles produce measurably distinct cross-sections",styles[-1]-styles[0] > 0.2)
	var cfg := WorldConfig.new()
	cfg.density_mode = 1
	cfg.mountain_morphology_enabled = true
	cfg.hydrology_enabled = false
	var surface := GeographicSurface.new(cfg)
	var old_cfg := cfg.duplicate_config()
	old_cfg.mountain_morphology_enabled = false
	var old := GeographicSurface.new(old_cfg)
	var maxima := Vector2.ZERO
	var high_counts := Vector2i.ZERO
	for z in range(-1728,-1215,8):
		for x in range(-256,257,8):
			var a := old.get_surface_height(x,z)
			var b := surface.get_surface_height(x,z)
			maxima.x = maxf(maxima.x,a); maxima.y = maxf(maxima.y,b)
			if a > 80: high_counts.x += 1
			if b > 80: high_counts.y += 1
	report.check("actual mountain maximum retained within ten percent",maxima.y > 100 and maxima.y >= maxima.x*0.9 and maxima.y <= maxima.x*1.25,str(maxima))
	report.check("actual high mountain mass increases",high_counts.y > high_counts.x,str(high_counts))
	var d := TerrainDensity.new(surface)
	var origin := Vector3i(-128,80,-1472)
	var size := Vector3i(16,16,16)
	var values := d.sample_block(origin,size)
	var rebuilt := TerrainDensity.new(GeographicSurface.new(cfg))
	report.check("negative-coordinate reconstruction deterministic",values == rebuilt.sample_block(origin,size))
	var other_cfg := cfg.duplicate_config()
	other_cfg.world_seed = 90210
	report.check("refined profile world changes with seed",values != TerrainDensity.new(GeographicSurface.new(other_cfg)).sample_block(origin,size))
	var workers: Array[Thread] = []
	for i in range(4):
		var worker := Thread.new()
		worker.start(func(): return d.sample_block(origin,size))
		workers.append(worker)
	var same := true
	for worker in workers: same = same and worker.wait_to_finish() == values
	report.check("four-worker morphology/density identity",same)
	var whole := d.sample_block(origin,Vector3i(32,16,16))
	var right := d.sample_block(origin+Vector3i(16,0,0),size)
	var seams := true
	for z in range(16):
		for x in range(32):
			for y in range(16):
				var expected := values[(z*16+x)*16+y] if x < 16 else right[(z*16+x-16)*16+y]
				seams = seams and absf(whole[(z*32+x)*16+y]-expected) < 0.0001
	report.check("density chunk partition is identical",seams)
	var blocky := TerrainBlockGenerator.new()
	var smooth := TerrainSmoothGenerator.new()
	blocky.configure(surface,BlockPalette.new(),d); smooth.configure(surface,d)
	report.check("both adapters still share the same density",blocky.get_density() == smooth.get_density())
	var max_transition := 0.0
	for x in range(-160,96): max_transition = maxf(max_transition,absf(surface.get_surface_height(x+1,-1440)-surface.get_surface_height(x,-1440)))
	report.check("mountain/foothill/valley transect continuous",max_transition < 10,"max column step="+str(max_transition))
	cfg.hydrology_enabled = true
	var wet := TerrainDensity.new(GeographicSurface.new(cfg))
	preload("res://tests/suites/m5_density_suite.gd")._test_hydrology(report,wet)
	
	# The M5 summit basin changes under the refined composition; this cell
	# is in the independently surveyed lake:1:-46 (final lake-survey.txt).
	var lake := wet.surface.get_water_at(32,-1480)
	report.check("refined mountains retain surveyed basin lake",lake.kind == "lake",str(lake))

	var edges: Dictionary = {}
	var lakes: Dictionary = {}
	for z in range(-768,257,128):
		for x in range(-256,513,128):
			var tile := wet.surface.get_drainage().tile_at(Vector2i(x,z))
			for edge in tile.segments: edges[str(edge.a)+str(edge.b)] = edge
			for body in tile.lakes: lakes[body.id] = body
	var descending := true
	var widths := true
	var joined := false
	var falls := 0
	for edge in edges.values():
		descending = descending and edge.ya >= edge.yb-0.0001
		widths = widths and edge.wa > 0 and edge.wb > 0
		joined = joined or edge.flow_b > 1
		if edge.waterfall and edge.drop >= 8: falls += 1
	report.check("refined terrain preserves river network and tributaries",edges.size() > 20 and joined)
	report.check("refined terrain preserves descending water levels and widths",descending and widths and not edges.is_empty())
	report.check("refined terrain retains waterfall candidates",falls > 0,str(falls))
	report.check("refined terrain retains multiple basin lakes",lakes.size() >= 2,str(lakes.size()))

static func run_scene_checks(report,tree: SceneTree) -> void:
	await tree.process_frame
	for path in ["res://scenes/main.tscn","res://scenes/smooth_terrain.tscn"]:
		var scene = load(path).instantiate()
		tree.root.add_child(scene)
		# Exercise a rendered scene, not destruction before its first draw.
		# GLES sky initialization is deferred; pre-draw teardown leaked textures.
		await tree.process_frame
		await tree.process_frame
		var world: VoxelWorld = scene.world
		report.check(path+" M5.1 shares world density",world.config.mountain_morphology_enabled and world.get_density() == world.get_generator().get_density())
		scene.camera.focus_on(Vector3(-16,100,-1360))
		var pose: Transform3D = scene.camera.global_transform
		scene._toggle_mountain_mode()
		report.check(path+" M5 comparison preserves orbit pose",not world.config.mountain_morphology_enabled and world.config.density_mode == 1 and scene.camera.global_transform.is_equal_approx(pose))
		scene.camera.set_fly_mode(true)
		scene.camera.global_position += Vector3(8,12,-9)
		pose = scene.camera.global_transform
		scene._toggle_mountain_mode()
		report.check(path+" morphology toggle preserves flight pose",world.config.mountain_morphology_enabled and scene.camera.global_transform.is_equal_approx(pose))
		var radius: int = world.config.view_distance_voxels
		scene._show_mountain_demo()
		report.check(path+" tour applies resource without raising streaming budget",world.config.mountain_profiles[0].id == &"alpine" and world.config.view_distance_voxels == radius and scene.camera.target == MountainShowcase.SITES[0].target)
		scene.queue_free()
		await tree.process_frame
		await tree.process_frame
