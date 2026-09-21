# Sky.SunTextureId, MoonTextureId, MoonAngularSize and StarCount, checked headless through the
# shader parameters they feed: the numbers, where sun and moon sit, and that a Sky asking for
# none of them keeps Godot's own procedural sky.
#
#   godot --headless --path . -s res://tests/sky_test.gd
extends SceneTree

var passed := 0
var failed := 0
var world: PulseBlockzWorld
var env: WorldEnvironment

func check(ok: bool, what: String) -> void:
	if ok: passed += 1; print("  PASS ", what)
	else: failed += 1; printerr("  FAIL ", what)

func _initialize() -> void:
	print("the sky")
	var main: Node = load("res://Main.tscn").instantiate()
	get_root().add_child(main)
	world = main.get_node("World")
	_run()

## The sky's material: Godot's ProceduralSkyMaterial, or the ShaderMaterial that takes over.
func _material() -> Resource:
	if env == null:
		env = world.get_node_or_null("Lighting")
	if env == null:
		return null
	var e: Environment = env.get_environment()
	if e == null or e.get_sky() == null:
		return null
	return e.get_sky().get_material()

func _set_sky(props: String) -> void:
	world.run_chunk("sky_probe", """
local l = game:GetService("Lighting")
local s = l:FindFirstChildOfClass("Sky")
if not s then s = Instance.new("Sky") s.Parent = l end
%s
""" % props)
	await create_timer(0.4).timeout

func _clock(t: float) -> void:
	world.run_chunk("sky_clock", 'game:GetService("Lighting").ClockTime = %f' % t)
	await create_timer(0.3).timeout

func _run() -> void:
	await create_timer(3.0).timeout

	# The town ships a six-face skybox, so the shader sky is already up: clear the faces first.
	await _set_sky("""
s.SkyboxRt = "" s.SkyboxLf = "" s.SkyboxUp = "" s.SkyboxDn = "" s.SkyboxBk = "" s.SkyboxFt = ""
s.SunTextureId = "" s.MoonTextureId = "" s.StarCount = 0
""")
	var plain := _material()
	check(plain != null and plain is ProceduralSkyMaterial,
		"a Sky asking for nothing keeps Godot's own sky, exactly as before")

	await _set_sky("s.StarCount = 3000")
	var mat = _material()
	check(mat != null and mat is ShaderMaterial, "asking for stars takes the sky over")
	if mat == null or not (mat is ShaderMaterial):
		print("%d passed, %d failed" % [passed, failed])
		quit(1)
		return
	var sm: ShaderMaterial = mat
	check(not bool(sm.get_shader_parameter("has_faces")),
		"and there is no cubemap behind them, because none was asked for")
	# star_chance is per cell on a shell of about 4*pi*star_scale^2 cells, so the product of the
	# two is the number of stars drawn.
	var scale := float(sm.get_shader_parameter("star_scale"))
	var chance := float(sm.get_shader_parameter("star_chance"))
	check(scale > 0.0, "the stars have a scale to be scattered across")
	check(abs(chance * 4.0 * PI * scale * scale - 3000.0) < 1.0,
		"and the cells that hold one come to about the count asked for")
	await _set_sky("s.StarCount = 12000")
	check(abs(float(sm.get_shader_parameter("star_chance")) * 4.0 * PI * scale * scale - 12000.0) < 1.0,
		"asking for four times as many fills four times as many cells")

	# Roblox's AngularSize is degrees across the whole body; the shader takes the cosine of half.
	await _set_sky("s.MoonAngularSize = 60 s.SunAngularSize = 20")
	check(abs(float(sm.get_shader_parameter("moon_cos")) - cos(deg_to_rad(30.0))) < 0.0005,
		"a 60-degree moon is a disc 30 degrees from its centre to its edge")
	check(abs(float(sm.get_shader_parameter("sun_cos")) - cos(deg_to_rad(10.0))) < 0.0005,
		"and a 20-degree sun, 10")
	await _set_sky("s.MoonAngularSize = 0")
	check(abs(float(sm.get_shader_parameter("moon_cos")) - 1.0) < 0.0001,
		"a moon of no size draws nothing rather than filling the sky")

	await _clock(12.0)
	var noon: Vector3 = sm.get_shader_parameter("sun_dir")
	var light: DirectionalLight3D = world.get_node_or_null("Sun")
	check(light != null, "there is a sun to compare against")
	if light != null:
		# A DirectionalLight3D travels along its -Z, so the way to look toward the sun is basis.z.
		check(noon.dot(light.global_transform.basis.z) > 0.999,
			"the sun is drawn where the light comes from, at noon")
	check(noon.y > 0.99, "and at noon that is overhead")
	check((sm.get_shader_parameter("moon_dir") as Vector3).dot(noon) < -0.999,
		"with the moon opposite it, as Studio has them")
	await _clock(0.0)
	check((sm.get_shader_parameter("sun_dir") as Vector3).y < -0.99, "at midnight the sun is under the world")
	check(float(sm.get_shader_parameter("star_fade")) > 0.99, "which is when the stars are out")
	await _clock(12.0)
	check(float(sm.get_shader_parameter("star_fade")) < 0.01, "and by noon they are gone")

	await _set_sky("s.CelestialBodiesShown = false")
	check(float(sm.get_shader_parameter("sun_show")) == 0.0 and float(sm.get_shader_parameter("moon_show")) == 0.0,
		"CelestialBodiesShown hides both of them, not just the sun")

	await _set_sky("s.StarCount = 0 s.MoonAngularSize = 11 s.SunTextureId = \"\" s.MoonTextureId = \"\"")
	var back = _material()
	check(back != null and back is ProceduralSkyMaterial,
		"a Sky that stops asking gets its sky back, not a black shader")

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)
