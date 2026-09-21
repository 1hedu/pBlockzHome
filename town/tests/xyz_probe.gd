# Engine probe, not a test of this project: whether Godot honours a CurveXYZTexture on
# ParticleProcessMaterial.scale_curve. Left blob is a plain CurveTexture, right is the XYZ one.
extends SceneTree
func _initialize() -> void:
	root.size = Vector2i(900, 500)
	var cam := Camera3D.new(); cam.position = Vector3(0, 0, 14); root.add_child(cam)
	var l := DirectionalLight3D.new(); root.add_child(l)
	for i in 2:
		var p := GPUParticles3D.new()
		p.amount = 1
		p.lifetime = 6.0
		p.explosiveness = 0.0
		p.position = Vector3(-3.0 + i * 6.0, 0, 0)
		var q := QuadMesh.new(); q.size = Vector2(1, 1)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 0.2, 0.8)
		# The project's own emitter billboards its particles, so the probe takes a mode too: first
		# user arg, 1 enabled, 2 particles, 3 fixed-Y, 4/5 those two with keep_scale.
		var mode := int(OS.get_cmdline_user_args()[0]) if OS.get_cmdline_user_args().size() > 0 else 0
		if mode == 1: mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		elif mode == 2: mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		elif mode == 3: mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
		if mode >= 4:
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if mode == 5 else BaseMaterial3D.BILLBOARD_ENABLED
			mat.billboard_keep_scale = true
		q.material = mat
		p.draw_pass_1 = q
		var pm := ParticleProcessMaterial.new()
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 0
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 0.0
		pm.gravity = Vector3.ZERO
		pm.scale_min = 1.0
		pm.scale_max = 1.0
		var flat := Curve.new(); flat.min_value = 0; flat.max_value = 4
		flat.add_point(Vector2(0, 2)); flat.add_point(Vector2(1, 2))
		if i == 0:
			var ct := CurveTexture.new(); ct.curve = flat
			pm.scale_curve = ct
		else:
			var tall := Curve.new(); tall.min_value = 0; tall.max_value = 4
			tall.add_point(Vector2(0, 4)); tall.add_point(Vector2(1, 4))
			var xyz := CurveXYZTexture.new()
			xyz.curve_x = flat; xyz.curve_y = tall; xyz.curve_z = flat
			pm.scale_curve = xyz
		p.process_material = pm
		root.add_child(p)
		p.restart()
	_shoot.call_deferred()

func _shoot() -> void:
	for i in 90:
		await process_frame
	var img := root.get_texture().get_image()
	img.save_png("user://shots/xyz_billboard.png")
	var w := img.get_width(); var h := img.get_height()
	for side in 2:
		var x0 := 0 if side == 0 else w / 2
		var x1 := w / 2 if side == 0 else w
		var n := 0; var miny := h; var maxy := -1; var minx := w; var maxx := -1
		for y in range(h):
			for x in range(x0, x1):
				var c := img.get_pixel(x, y)
				if c.r > 0.5 and c.b > 0.4 and c.g < c.r - 0.2:
					n += 1
					miny = min(miny, y); maxy = max(maxy, y)
					minx = min(minx, x); maxx = max(maxx, x)
		var label := "CurveTexture (flat 2)" if side == 0 else "CurveXYZTexture (y=4)"
		if n == 0: print("  %-24s nothing drawn" % label)
		else: print("  %-24s %d px, %d wide, %d tall" % [label, n, maxx - minx + 1, maxy - miny + 1])
	quit(0)
