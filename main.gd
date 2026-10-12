extends Node2D
## STRANDED - Portfolio #2 - Arcade (gaya Duck Hunt, 2D).
## Semua visual masih PLACEHOLDER yang digambar lewat kode (_draw).
## Ganti dengan sprite asli nanti; logika game tidak perlu diubah.
##
## Tampilan 2.5D + lighting malam (cahaya bulan):
##   - dunia  (normal)     : langit, bulan, bukit berlapis (parallax), mahluk, tangan
##   - shade  (multiply)   : ambient malam kebiruan + vignette (memerah saat kelaparan)
##   - light  (additive)   : cahaya bulan, tangan, proyektil, ledakan, kunang-kunang
##   - ui     (normal)     : HUD, dialog, menu, kursor (tidak ikut digelapkan)

const LayerScript := preload("res://layer.gd")

const W := 1280.0
const H := 720.0

const MAX_BULLETS := 6
const MAX_HUNGER := 10.0
const HIT_GAIN := 2.0         # kena tembak: +2 kotak (semua jenis mahluk)
const MISS_PENALTY := 1.0     # meleset: -1 kotak
const CREATURE_R := 38.0
const HIT_PAD := 10.0
const HAND_POS := Vector2(640, 705)
const GROUND_Y := 655.0       # garis tanah dekat (tempat bayangan mahluk jatuh)

const MOON_POS := Vector2(1050, 170)
const AMBIENT := Color(0.68, 0.74, 0.96)        # malam kebiruan
const AMBIENT_DANGER := Color(0.98, 0.55, 0.55) # saat perut hampir kosong

const KIND_COLORS := [Color(0.95, 0.55, 0.15), Color(0.65, 0.35, 0.85), Color(0.3, 0.8, 0.45)]
const KIND_NAMES := ["Mahluk A", "Mahluk B", "Mahluk C"]

## 5 level. Tiap level makin susah lewat:
##   decay  = detik per 1 kotak lapar turun (makin kecil = makin cepat lapar)
##   start  = isi bar lapar di awal level
##   speed  = pengali kecepatan terbang mahluk
##   weights= peluang muncul Mahluk A / B (kecil, zigzag, cepat) / C
## Disetel lewat simulasi; ubah angka di sini untuk menyetel ulang.
const LEVELS := [
	{"decay": 18.0, "start": 6.0, "speed": 0.80, "weights": [0.6, 0.0, 0.4],
		"intro": ""},
	{"decay": 14.0, "start": 5.0, "speed": 0.90, "weights": [0.45, 0.2, 0.35],
		"intro": "Bagus! Tapi perutmu cepat keroncongan lagi. Mahluk kecil yang lincah mulai muncul, bidik dengan sabar."},
	{"decay": 12.0, "start": 5.0, "speed": 1.00, "weights": [0.34, 0.33, 0.33],
		"intro": "Malam makin larut. Laparmu turun lebih cepat dari sebelumnya, dan mahluk-mahluk mulai waspada."},
	{"decay": 10.0, "start": 5.0, "speed": 1.08, "weights": [0.3, 0.4, 0.3],
		"intro": "Mereka terbang makin cepat sekarang. Jangan buru-buru menembak, satu tembakan meleset bisa berarti kelaparan."},
	{"decay": 8.5, "start": 5.0, "speed": 1.15, "weights": [0.25, 0.45, 0.3],
		"intro": "Ini perburuan terakhir malam ini. Laparmu menggerogoti cepat dan mahluknya paling liar. Fokus!"},
]

const TUTORIAL_STEPS := [
	{"text": "Halo, pendatang. Kamu terdampar di tempat asing dan perutmu keroncongan. Satu-satunya cara bertahan adalah berburu mahluk di sini.", "hl": ""},
	{"text": "Ini bar laparmu, sepuluh kotak. Ia turun pelan-pelan seiring waktu. Penuhi sampai penuh untuk lanjut. Ada lima level sampai kamu benar-benar kenyang.", "hl": "hunger"},
	{"text": "Ini tenagamu. Hanya ada enam tembakan, jadi jangan sia-siakan. Tembakan yang meleset akan mengurangi satu kotak laparmu.", "hl": "bullets"},
	{"text": "Mahluk terbang itu adalah makananmu. Setiap kali kena, bar laparmu terisi dua kotak.", "hl": "creature"},
	{"text": "Arahkan kursor untuk membidik, lalu klik untuk menembak dari tanganmu. Jika tenaga habis sebelum bar penuh, kamu mati kelaparan. Selamat berburu!", "hl": "hand"},
]

const WIN_LINES := [
	"Perutmu akhirnya terisi. Kekuatan di tanganmu ternyata cukup untuk bertahan di tempat asing ini.",
	"Tapi ini baru permulaan. Entah di mana kamu berada, dan entah bagaimana caranya pulang.",
	"Istirahatlah dulu. Besok kita cari jalan keluar.",
]
const FAIL_LINES := [
	"Tenagamu habis, dan perutmu masih kosong. Pandanganmu perlahan menggelap...",
	"Mungkin lain kali kamu harus lebih teliti membidik.",
]

const HIT_LINES := ["Kena! Terus begitu.", "Satu lagi masuk perut.", "Bidikan bagus!", "Mantap, pertahankan!"]
const MISS_LINES := ["Meleset... tenagamu terbuang.", "Sabar, bidik dulu.", "Aduh, perutmu makin keroncongan.", "Jangan asal tembak!"]

enum State { MENU, TUTORIAL, PLAY, END }

class Creature:
	var pos := Vector2.ZERO
	var vx := 0.0
	var vy := 0.0
	var base_y := 0.0
	var amp := 0.0
	var freq := 0.0
	var phase := 0.0
	var t := 0.0
	var flap := 0.0
	var spin := 0.0
	var scale := 1.0
	var kind := 0
	var hit := false

class Projectile:
	var origin := Vector2.ZERO
	var dest := Vector2.ZERO
	var t := 0.0
	var dur := 0.12
	var hit := false

class Fx:
	var pos := Vector2.ZERO
	var t := 0.0
	var dur := 0.3
	var hit := false

class Floater:
	var pos := Vector2.ZERO
	var t := 0.0
	var text := ""
	var col := Color.WHITE

class Spark:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var t := 0.0
	var life := 0.5
	var col := Color.WHITE

var state := State.MENU
var level := 0
var hunger := 5.0
var bullets := MAX_BULLETS
var creatures: Array = []
var projectiles: Array = []
var effects: Array = []
var floaters: Array = []
var sparks: Array = []
var spawn_cd := 0.0
var spawn_index := 0
var target_count := 3
var pending_result := ""
var result_timer := 0.0
var won := false
var show_about := false
var end_t := 0.0
var end_lines: Array = []
var end_step := 0
var tut_step := 0
var tut_chars := 0.0      # progres efek ketik (dipakai tutorial dan epilog)
var time := 0.0
var shake := 0.0
var flash := 0.0          # kilat cahaya saat menembak
var danger := 0.0         # 0..1, makin lapar makin merah suasananya
var banner_t := 0.0       # tulisan "LEVEL x" di awal level
var par := Vector2.ZERO   # parallax mengikuti kursor
var comment_text := ""
var comment_t := 0.0
var comment_total := 2.0
var comment_pos := true
var warned_low := false
var warned_zero := false
var mouse := Vector2(640, 300)
var font: Font
var dialog_label: Label
var panel_style: StyleBoxFlat
var bubble_style: StyleBoxFlat
var glow_tex: GradientTexture2D
var vignette_tex: GradientTexture2D
var shade_layer: Node2D
var light_layer: Node2D
var ui_layer: Node2D
var cv: CanvasItem         # kanvas aktif (dunia / shade / light / ui)


func _ready() -> void:
	randomize()
	font = ThemeDB.fallback_font
	cv = self
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color(1.0, 0.96, 0.85)
	panel_style.border_color = Color(0.5, 0.3, 0.15)
	panel_style.set_border_width_all(5)
	panel_style.set_corner_radius_all(20)

	bubble_style = StyleBoxFlat.new()
	bubble_style.bg_color = Color(1.0, 0.98, 0.92)
	bubble_style.border_color = Color(0.5, 0.3, 0.15)
	bubble_style.set_border_width_all(3)
	bubble_style.set_corner_radius_all(14)

	# Tekstur cahaya bulat lembut (dipakai untuk glow dan bayangan)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.45), Color(1, 1, 1, 0)])
	glow_tex = GradientTexture2D.new()
	glow_tex.gradient = g
	glow_tex.fill = GradientTexture2D.FILL_RADIAL
	glow_tex.fill_from = Vector2(0.5, 0.5)
	glow_tex.fill_to = Vector2(1.0, 0.5)
	glow_tex.width = 128
	glow_tex.height = 128

	# Vignette: tengah terang, tepi gelap (dipakai di lapisan multiply)
	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	vg.colors = PackedColorArray([Color(1, 1, 1), Color(1, 1, 1), Color(0.48, 0.5, 0.62)])
	vignette_tex = GradientTexture2D.new()
	vignette_tex.gradient = vg
	vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	vignette_tex.fill_from = Vector2(0.5, 0.5)
	vignette_tex.fill_to = Vector2(1.0, 0.5)
	vignette_tex.width = 256
	vignette_tex.height = 256

	shade_layer = _make_layer("_layer_shade", _blend(CanvasItemMaterial.BLEND_MODE_MUL))
	light_layer = _make_layer("_layer_light", _blend(CanvasItemMaterial.BLEND_MODE_ADD))
	ui_layer = _make_layer("_layer_ui", null)

	dialog_label = Label.new()
	dialog_label.position = Vector2(345, 425)
	dialog_label.size = Vector2(590, 140)
	dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog_label.add_theme_font_size_override("font_size", 22)
	dialog_label.add_theme_color_override("font_color", Color(0.15, 0.1, 0.05))
	dialog_label.visible = false
	add_child(dialog_label)


func _blend(mode: CanvasItemMaterial.BlendMode) -> CanvasItemMaterial:
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = mode
	return mat


func _make_layer(fn: String, mat: Material) -> Node2D:
	var n := Node2D.new()
	n.set_script(LayerScript)
	n.set("host", self)
	n.set("fn", fn)
	n.material = mat
	add_child(n)
	return n


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if show_about:
				show_about = false
			else:
				get_tree().quit()
		elif event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if state == State.TUTORIAL:
				_advance_tutorial()
			elif state == State.END and end_t > 0.6 and end_step < end_lines.size():
				_advance_end()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_click(get_local_mouse_position())


func _on_click(m: Vector2) -> void:
	match state:
		State.MENU:
			if show_about:
				show_about = false
			elif Rect2(490, 320, 300, 64).has_point(m):
				_start_tutorial()
			elif Rect2(490, 400, 300, 64).has_point(m):
				show_about = true
			elif Rect2(490, 480, 300, 64).has_point(m):
				get_tree().quit()
		State.TUTORIAL:
			_advance_tutorial()
		State.PLAY:
			_shoot(m)
		State.END:
			if end_t < 0.6:
				return
			if end_step < end_lines.size():
				_advance_end()
			elif Rect2(400, 440, 220, 70).has_point(m):
				if won:
					level = 0      # tamat: main lagi dari level 1
				_start_play()      # kalah: coba lagi level yang sama
			elif Rect2(660, 440, 220, 70).has_point(m):
				_go_menu()


# ---------------------------------------------------------------- flow

func _cfg() -> Dictionary:
	return LEVELS[level]


func _final_level() -> bool:
	return level >= LEVELS.size() - 1


func _reset_round() -> void:
	hunger = float(_cfg()["start"])
	bullets = MAX_BULLETS
	creatures.clear()
	projectiles.clear()
	effects.clear()
	floaters.clear()
	sparks.clear()
	pending_result = ""
	result_timer = 0.0
	spawn_cd = 0.3
	spawn_index = 0
	shake = 0.0
	flash = 0.0
	comment_t = 0.0
	warned_low = false
	warned_zero = false


func _go_menu() -> void:
	level = 0
	_reset_round()
	state = State.MENU
	target_count = 3
	dialog_label.visible = false


func _start_tutorial() -> void:
	level = 0
	_reset_round()
	state = State.TUTORIAL
	target_count = 1
	tut_step = 0
	dialog_label.visible = true
	_set_tut_text()


func _set_tut_text() -> void:
	dialog_label.text = TUTORIAL_STEPS[tut_step]["text"]
	dialog_label.visible_characters = 0
	tut_chars = 0.0


func _typing_done() -> bool:
	return tut_chars >= float(dialog_label.text.length())


func _advance_tutorial() -> void:
	if not _typing_done():
		tut_chars = 9999.0   # selesaikan ketikan dulu
		return
	tut_step += 1
	if tut_step >= TUTORIAL_STEPS.size():
		_start_play()
	else:
		_set_tut_text()


func _start_play() -> void:
	_reset_round()
	state = State.PLAY
	target_count = 2
	banner_t = 1.6
	dialog_label.visible = false


func _enter_end() -> void:
	won = pending_result == "win"
	state = State.END
	end_t = 0.0
	if won and not _final_level():
		end_lines = [LEVELS[level + 1]["intro"]]   # transisi ke level berikutnya
	else:
		end_lines = WIN_LINES if won else FAIL_LINES
	end_step = 0
	dialog_label.visible = true
	dialog_label.text = end_lines[0]
	dialog_label.visible_characters = 0
	tut_chars = 0.0


func _advance_end() -> void:
	if not _typing_done():
		tut_chars = 9999.0
		return
	end_step += 1
	if end_step < end_lines.size():
		dialog_label.text = end_lines[end_step]
		dialog_label.visible_characters = 0
		tut_chars = 0.0
	else:
		dialog_label.visible = false
		if won and not _final_level():
			level += 1
			_start_play()


# ---------------------------------------------------------------- update

func _process(delta: float) -> void:
	time += delta
	mouse = get_local_mouse_position()

	# parallax halus mengikuti kursor
	var target := Vector2(clampf((mouse.x - W * 0.5) / (W * 0.5), -1.0, 1.0), clampf((mouse.y - H * 0.5) / (H * 0.5), -1.0, 1.0))
	par = par.lerp(target, 1.0 - exp(-3.0 * delta))

	# suasana memerah saat perut hampir kosong
	var danger_target := 0.0
	if state == State.PLAY:
		danger_target = clampf((3.0 - hunger) / 3.0, 0.0, 1.0)
	elif state == State.END and not won:
		danger_target = 0.6
	danger = lerpf(danger, danger_target, 1.0 - exp(-2.5 * delta))
	flash = maxf(0.0, flash - delta * 5.0)
	banner_t = maxf(0.0, banner_t - delta)

	if state != State.END:
		_update_creatures(delta)

	if state == State.TUTORIAL or (state == State.END and end_step < end_lines.size()):
		if not _typing_done():
			tut_chars += delta * 45.0
			dialog_label.visible_characters = int(tut_chars)
		else:
			dialog_label.visible_characters = -1

	if state == State.PLAY:
		comment_t = maxf(0.0, comment_t - delta)
		if pending_result == "":
			hunger = maxf(0.0, hunger - delta / float(_cfg()["decay"]))
			_check_warnings()
		else:
			result_timer -= delta
			if result_timer <= 0.0:
				_enter_end()

	if state == State.END:
		end_t += delta

	if shake > 0.1:
		position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake
		shake *= exp(-9.0 * delta)
	else:
		shake = 0.0
		position = Vector2.ZERO

	_update_vfx(delta)
	queue_redraw()
	shade_layer.queue_redraw()
	light_layer.queue_redraw()
	ui_layer.queue_redraw()


func _check_warnings() -> void:
	if hunger > 3.0:
		warned_low = false
	if hunger > 0.5:
		warned_zero = false
	if comment_t > 0.0:
		return
	if hunger <= 0.0 and not warned_zero:
		warned_zero = true
		_say("Kamu kelaparan! Cepat tembak!", false, 2.5)
	elif hunger <= 2.0 and not warned_low:
		warned_low = true
		_say("Perutmu hampir kosong!", false, 2.2)


func _say(text: String, positive: bool, secs: float = 2.0) -> void:
	comment_text = text
	comment_t = secs
	comment_total = secs
	comment_pos = positive


func _update_creatures(delta: float) -> void:
	if creatures.size() < target_count and pending_result == "":
		spawn_cd -= delta
		if spawn_cd <= 0.0:
			_spawn_creature()
			spawn_cd = 0.5

	for i in range(creatures.size() - 1, -1, -1):
		var c: Creature = creatures[i]
		c.t += delta
		if not c.hit:
			c.pos.x += c.vx * delta
			c.pos.y = c.base_y + sin(c.t * c.freq + c.phase) * c.amp
			c.flap += delta * 14.0
			if c.pos.x < -90.0 or c.pos.x > W + 90.0:
				creatures.remove_at(i)   # kabur, nanti digantikan
		else:
			c.vy += 900.0 * delta
			c.pos.y += c.vy * delta
			c.pos.x += c.vx * 0.2 * delta
			c.spin += delta * 8.0
			if c.pos.y > H + 90.0:
				creatures.remove_at(i)


func _spawn_creature() -> void:
	var c := Creature.new()
	var in_play := state == State.PLAY
	var from_left := randf() < 0.5
	c.kind = _pick_kind() if in_play else spawn_index % 3
	spawn_index += 1

	# Perilaku tiap jenis berbeda. Nilai isi bar tetap sama (+2).
	var speed := 150.0
	match c.kind:
		0:   # A: terbang lurus, pelan
			speed = randf_range(120.0, 160.0)
			c.amp = randf_range(8.0, 18.0)
			c.freq = randf_range(1.5, 2.5)
			c.scale = 1.0
		1:   # B: zigzag, cepat, kecil
			speed = randf_range(260.0, 340.0)
			c.amp = randf_range(45.0, 65.0)
			c.freq = randf_range(5.0, 7.0)
			c.scale = 0.8
		_:   # C: melayang naik-turun, lambat, besar
			speed = randf_range(90.0, 130.0)
			c.amp = randf_range(70.0, 95.0)
			c.freq = randf_range(1.0, 1.6)
			c.scale = 1.15
	if in_play:
		speed *= float(_cfg()["speed"])
	else:
		speed *= 0.8   # menu dan tutorial lebih santai

	var top_limit := 100.0
	var bottom_limit := 520.0 if in_play else 330.0
	var lo := top_limit + c.amp
	var hi := bottom_limit - c.amp
	c.base_y = randf_range(lo, hi) if hi > lo else (top_limit + bottom_limit) * 0.5
	c.phase = randf() * TAU
	c.vx = speed if from_left else -speed
	c.pos = Vector2(-60.0 if from_left else W + 60.0, c.base_y)
	creatures.append(c)


func _pick_kind() -> int:
	var w: Array = _cfg()["weights"]
	var r := randf()
	for k in w.size():
		r -= float(w[k])
		if r <= 0.0:
			return k
	return 0


func _update_vfx(delta: float) -> void:
	for i in range(projectiles.size() - 1, -1, -1):
		var p: Projectile = projectiles[i]
		p.t += delta
		if p.t >= p.dur:
			var fx := Fx.new()
			fx.pos = p.dest
			fx.hit = p.hit
			fx.dur = 0.4 if p.hit else 0.25
			effects.append(fx)
			projectiles.remove_at(i)
	for i in range(effects.size() - 1, -1, -1):
		var fx: Fx = effects[i]
		fx.t += delta
		if fx.t >= fx.dur:
			effects.remove_at(i)
	for i in range(floaters.size() - 1, -1, -1):
		var f: Floater = floaters[i]
		f.t += delta
		f.pos.y -= 50.0 * delta
		if f.t > 0.9:
			floaters.remove_at(i)
	for i in range(sparks.size() - 1, -1, -1):
		var s: Spark = sparks[i]
		s.t += delta
		s.vel.y += 500.0 * delta
		s.pos += s.vel * delta
		if s.t >= s.life:
			sparks.remove_at(i)


# ---------------------------------------------------------------- shooting

func _aim_dir() -> Vector2:
	var a := (mouse - HAND_POS).angle()
	if a >= 0.0:
		a = -0.15 if a < PI * 0.5 else -PI + 0.15
	a = clampf(a, -PI + 0.15, -0.15)
	return Vector2.from_angle(a)


func _hand_tip() -> Vector2:
	return HAND_POS + _aim_dir() * 72.0


func _shoot(m: Vector2) -> void:
	if bullets <= 0 or pending_result != "":
		return
	bullets -= 1
	flash = 1.0

	var best: Creature = null
	var best_d := 1.0e9
	for c in creatures:
		if c.hit:
			continue
		var d: float = c.pos.distance_to(m)
		if d <= CREATURE_R * c.scale + HIT_PAD and d < best_d:
			best = c
			best_d = d

	var p := Projectile.new()
	p.origin = _hand_tip()
	p.dest = m
	p.hit = best != null
	projectiles.append(p)

	var f := Floater.new()
	if best != null:
		best.hit = true
		best.vy = -200.0
		hunger = minf(MAX_HUNGER, hunger + HIT_GAIN)
		f.pos = best.pos + Vector2(-50, -50)
		f.text = "+2"
		f.col = Color(0.5, 1.0, 0.6)
		for j in 14:
			var s := Spark.new()
			s.pos = best.pos
			s.vel = Vector2.from_angle(randf() * TAU) * randf_range(80.0, 260.0)
			s.life = randf_range(0.35, 0.6)
			s.col = KIND_COLORS[best.kind].lightened(0.3)
			sparks.append(s)
		shake = 9.0
	else:
		hunger = maxf(0.0, hunger - MISS_PENALTY)
		f.pos = m + Vector2(-50, -30)
		f.text = "-1"
		f.col = Color(1.0, 0.45, 0.45)
		shake = 4.0
	floaters.append(f)

	if hunger >= MAX_HUNGER - 0.0001:
		pending_result = "win"
		result_timer = 1.1
		_say("Perutmu akhirnya penuh!", true, 1.2)
	elif bullets == 0:
		pending_result = "fail"
		result_timer = 1.1
		_say("Tenagamu habis...", false, 1.2)
	elif bullets == 1:
		_say("Tinggal satu tembakan!", false, 2.5)
	elif best != null:
		_say(HIT_LINES.pick_random(), true)
	else:
		_say(MISS_LINES.pick_random(), false)


# ---------------------------------------------------------------- draw helpers

func _text(pos: Vector2, s: String, size: int, col: Color, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	cv.draw_string(font, pos, s, align, width, size, col)


func _ellipse(rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _ellipse_at(c: Vector2, rx: float, ry: float, n: int = 20) -> PackedVector2Array:
	var pts := _ellipse(rx, ry, n)
	for i in pts.size():
		pts[i] += c
	return pts


## Cahaya/bayangan bulat lembut. Di lapisan cahaya = glow, di dunia (warna hitam) = bayangan.
func _glow(pos: Vector2, r: float, col: Color) -> void:
	cv.draw_texture_rect(glow_tex, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false, col)


func _soft_shadow(rect: Rect2, alpha: float) -> void:
	cv.draw_texture_rect(glow_tex, rect, false, Color(0, 0, 0, alpha))


## Offset parallax: makin besar depth, makin banyak bergeser (lawan arah kursor).
func _par_off(depth: float) -> Vector2:
	return -par * depth + Vector2(sin(time * 0.2) * depth * 0.15, 0.0)


## Kunang-kunang: melayang pelan, posisi deterministik dari indeks.
func _firefly_pos(i: int, depth: float) -> Vector2:
	var fi := float(i)
	var x := fmod(fi * 173.0 + time * (8.0 + fmod(fi * 3.7, 10.0)), W + 80.0) - 40.0
	var y := 380.0 + fmod(fi * 61.0, 240.0) + sin(time * 0.9 + fi * 1.7) * 18.0
	return Vector2(x, y) + _par_off(depth)


func _button(r: Rect2, label: String) -> void:
	var hover := r.has_point(mouse)
	cv.draw_rect(r, Color(0.2, 0.7, 0.5) if hover else Color(0.15, 0.5, 0.4))
	cv.draw_rect(r, Color.WHITE, false, 3.0)
	_text(Vector2(r.position.x, r.position.y + r.size.y * 0.64), label, 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


# ---------------------------------------------------------------- draw entry points

func _draw() -> void:
	cv = self
	_draw_world()


func _layer_shade(c: CanvasItem) -> void:
	cv = c
	# malam makin larut tiap level (sedikit lebih gelap)
	var night := 0.0 if state == State.MENU else float(level) * 0.035
	var amb := AMBIENT.darkened(night).lerp(AMBIENT_DANGER, danger * 0.7)
	cv.draw_rect(Rect2(-60, -60, W + 120, H + 120), amb)
	cv.draw_texture_rect(vignette_tex, Rect2(-60, -60, W + 120, H + 120), false)
	cv = self


func _layer_light(c: CanvasItem) -> void:
	cv = c
	_draw_lights()
	cv = self


func _layer_ui(c: CanvasItem) -> void:
	cv = c
	_draw_ui()
	cv = self


# ---------------------------------------------------------------- world

func _draw_world() -> void:
	_draw_background()
	for c in creatures:
		_draw_creature_shadow(c)
	for c in creatures:
		_draw_creature(c)
	if state != State.MENU:
		_draw_vfx_world()
	_draw_foreground()
	if state != State.MENU:
		_draw_hand()


func _draw_background() -> void:
	# langit malam: biru tua -> biru keabu di cakrawala
	var top := Color("#16223f")
	var mid := Color("#2c4266")
	var hor := Color("#7a98b8")
	cv.draw_polygon(PackedVector2Array([Vector2(-60, -60), Vector2(W + 60, -60), Vector2(W + 60, 280), Vector2(-60, 280)]), PackedColorArray([top, top, mid, mid]))
	cv.draw_polygon(PackedVector2Array([Vector2(-60, 280), Vector2(W + 60, 280), Vector2(W + 60, 560), Vector2(-60, 560)]), PackedColorArray([mid, mid, hor, hor]))

	# bintang berkelip (lapisan paling jauh)
	var so := _par_off(3.0)
	for i in 60:
		var sx := fmod(float(i) * 137.0, W) + so.x
		var sy := fmod(float(i) * 71.0, 320.0) + 10.0 + so.y
		var tw := 0.3 + 0.3 * sin(time * (1.5 + fmod(float(i), 3.0)) + i)
		cv.draw_circle(Vector2(sx, sy), 1.0 + fmod(float(i), 2.0) * 0.5, Color(1, 1, 1, tw))

	# bulan + sorot cahaya tipis tepat di belakangnya
	var moon := MOON_POS + _par_off(5.0)
	for i in 8:
		var ang := float(i) / 8.0 * TAU + time * 0.03
		var p1 := moon + Vector2.from_angle(ang - 0.06) * 260.0
		var p2 := moon + Vector2.from_angle(ang + 0.06) * 260.0
		var ray := Color(0.85, 0.9, 1.0, 0.1)
		var none := Color(0.85, 0.9, 1.0, 0.0)
		cv.draw_polygon(PackedVector2Array([moon, p1, p2]), PackedColorArray([ray, none, none]))
	cv.draw_circle(moon, 48.0, Color(0.97, 0.95, 0.84))
	cv.draw_circle(moon + Vector2(-14, -8), 9.0, Color(0.88, 0.86, 0.76))
	cv.draw_circle(moon + Vector2(12, 14), 6.0, Color(0.88, 0.86, 0.76))

	# gunung jauh, kabut, bukit tengah + pepohonan, kabut
	_hills(470.0, 40.0, 0.005, 0.7, _par_off(9.0), Color(0.3, 0.38, 0.52), 560.0)
	_fog(500.0, 80.0, Color(0.75, 0.85, 1.0, 0.18), _par_off(11.0))
	_hills(565.0, 26.0, 0.009, 2.3, _par_off(16.0), Color(0.16, 0.26, 0.3), GROUND_Y + 30.0)
	_trees(_par_off(16.0))
	_fog(590.0, 60.0, Color(0.7, 0.82, 1.0, 0.16), _par_off(14.0))

	# tanah dekat (tempat bayangan mahluk jatuh)
	var g0 := Color(0.12, 0.2, 0.2)
	var g1 := Color(0.06, 0.1, 0.11)
	var go := _par_off(22.0)
	cv.draw_polygon(PackedVector2Array([Vector2(-60, GROUND_Y + go.y), Vector2(W + 60, GROUND_Y + go.y), Vector2(W + 60, H + 60), Vector2(-60, H + 60)]), PackedColorArray([g0, g0, g1, g1]))
	cv.draw_rect(Rect2(-60, GROUND_Y + go.y, W + 120, 2), Color(0.8, 0.9, 1.0, 0.18))
	_text(Vector2(W - 260, H - 10), "BACKGROUND (placeholder)", 12, Color(1, 1, 1, 0.4))


func _hills(base_y: float, amp: float, freq: float, phase: float, off: Vector2, col: Color, bottom: float) -> void:
	var pts := PackedVector2Array()
	pts.append(Vector2(-80, bottom + 40))
	var x := -80.0
	while x <= W + 80.0:
		pts.append(Vector2(x + off.x, base_y + off.y + sin(x * freq + phase) * amp + sin(x * freq * 2.7 + phase) * amp * 0.35))
		x += 32.0
	pts.append(Vector2(W + 80.0, bottom + 40))
	cv.draw_colored_polygon(pts, col)


func _trees(off: Vector2) -> void:
	var col := Color(0.1, 0.17, 0.2)
	for i in 14:
		var x := 40.0 + float(i) * 97.0 + fmod(float(i) * 41.0, 50.0) + off.x
		var base := 565.0 + off.y + sin(x * 0.009 + 2.3) * 26.0 + 14.0
		var h := 50.0 + fmod(float(i) * 29.0, 40.0)
		var w := h * 0.32
		cv.draw_colored_polygon(PackedVector2Array([Vector2(x - w, base), Vector2(x, base - h), Vector2(x + w, base)]), col)
		cv.draw_colored_polygon(PackedVector2Array([Vector2(x - w * 0.8, base - h * 0.35), Vector2(x, base - h * 1.15), Vector2(x + w * 0.8, base - h * 0.35)]), col)


func _fog(y: float, h: float, col: Color, off: Vector2) -> void:
	var clear := Color(col.r, col.g, col.b, 0.0)
	var y0 := y + off.y
	cv.draw_polygon(PackedVector2Array([Vector2(-60, y0 - h * 0.5), Vector2(W + 60, y0 - h * 0.5), Vector2(W + 60, y0), Vector2(-60, y0)]), PackedColorArray([clear, clear, col, col]))
	cv.draw_polygon(PackedVector2Array([Vector2(-60, y0), Vector2(W + 60, y0), Vector2(W + 60, y0 + h * 0.5), Vector2(-60, y0 + h * 0.5)]), PackedColorArray([col, col, clear, clear]))


func _draw_foreground() -> void:
	# siluet rumput & batu paling depan (bergeser paling jauh)
	var o := _par_off(34.0)
	var col := Color(0.03, 0.05, 0.07)
	for i in 34:
		var x := -60.0 + i * 42.0 + o.x
		var h := 16.0 + fmod(float(i) * 37.0, 30.0)
		var sway := sin(time * 1.3 + i) * 4.0
		cv.draw_colored_polygon(PackedVector2Array([Vector2(x - 8, H + 10), Vector2(x + sway, H - h), Vector2(x + 8, H + 10)]), col)
	cv.draw_colored_polygon(PackedVector2Array([Vector2(-60 + o.x, H + 10), Vector2(-40 + o.x, H - 70), Vector2(40 + o.x, H - 95), Vector2(120 + o.x, H - 40), Vector2(150 + o.x, H + 10)]), col)
	cv.draw_colored_polygon(PackedVector2Array([Vector2(W - 140 + o.x, H + 10), Vector2(W - 100 + o.x, H - 60), Vector2(W - 20 + o.x, H - 85), Vector2(W + 60 + o.x, H + 10)]), col)


func _draw_creature_shadow(c: Creature) -> void:
	# bayangan jatuh di tanah: makin tinggi terbang, makin besar & samar
	var gy := GROUND_Y + 14.0 + _par_off(22.0).y
	var height := maxf(0.0, gy - c.pos.y)
	var k := clampf(height / 600.0, 0.0, 1.0)
	var rx := 46.0 * c.scale * (0.8 + k * 0.8)
	var a := 0.45 * (1.0 - k * 0.7)
	_soft_shadow(Rect2(Vector2(c.pos.x - rx, gy - rx * 0.18), Vector2(rx * 2.0, rx * 0.36)), a)


func _draw_creature(c: Creature) -> void:
	var col: Color = KIND_COLORS[c.kind]
	var dir := 1.0 if c.vx >= 0.0 else -1.0
	var wing_col := col.darkened(0.3)
	var flap := sin(c.flap) * 24.0
	var sc := Vector2(dir * c.scale, c.scale)
	if c.hit:
		col = col.lerp(Color(0.55, 0.55, 0.6), 0.65)
		wing_col = col.darkened(0.2)
		flap = -14.0
		cv.draw_set_transform(c.pos, c.spin, sc)
	else:
		cv.draw_set_transform(c.pos, 0.0, sc)

	# sayap belakang (lebih gelap = lebih jauh) memberi kesan tebal
	cv.draw_colored_polygon(PackedVector2Array([Vector2(-6, -4), Vector2(-26, -24.0 + flap * 0.6), Vector2(14, -4)]), wing_col.darkened(0.35))
	match c.kind:
		0:
			cv.draw_circle(Vector2.ZERO, 30.0, col)
			cv.draw_colored_polygon(PackedVector2Array([Vector2(28, -4), Vector2(48, 6), Vector2(28, 12)]), Color(1.0, 0.85, 0.2))
		1:
			cv.draw_colored_polygon(PackedVector2Array([Vector2(-36, 0), Vector2(0, -34), Vector2(36, 0), Vector2(0, 34)]), col)
		_:
			cv.draw_colored_polygon(_ellipse(38.0, 26.0), col)
			cv.draw_colored_polygon(PackedVector2Array([Vector2(8, -22), Vector2(18, -40), Vector2(24, -18)]), col.darkened(0.25))
	# shading volume: perut gelap, punggung tersorot bulan
	cv.draw_colored_polygon(_ellipse_at(Vector2(0, 12), 16.0, 7.0), Color(0, 0, 0, 0.22))
	cv.draw_colored_polygon(_ellipse_at(Vector2(2, -12), 12.0, 5.0), Color(1, 1, 1, 0.28))
	# sayap depan
	cv.draw_colored_polygon(PackedVector2Array([Vector2(-14, -6), Vector2(-40, -30.0 - flap), Vector2(10, -6)]), wing_col)

	if c.hit:
		cv.draw_line(Vector2(8, -14), Vector2(20, -2), Color.BLACK, 3.0)
		cv.draw_line(Vector2(20, -14), Vector2(8, -2), Color.BLACK, 3.0)
	else:
		cv.draw_circle(Vector2(14, -8), 7.0, Color.WHITE)
		cv.draw_circle(Vector2(16, -8), 3.0, Color.BLACK)

	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var tag := "%s (kena)" % KIND_NAMES[c.kind] if c.hit else "%s (terbang)" % KIND_NAMES[c.kind]
	_text(c.pos + Vector2(-50, 62.0 * c.scale), tag, 12, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 100.0)


func _draw_hand() -> void:
	var dir := _aim_dir()
	var tip := _hand_tip()
	var skin := Color(0.96, 0.78, 0.62)
	var dark := skin.darkened(0.35)
	# lengan (sisi gelap dulu, lalu sisi terang = kesan silinder)
	cv.draw_line(HAND_POS + Vector2(0, 70), HAND_POS, dark, 44.0)
	cv.draw_line(HAND_POS + Vector2(6, 70), HAND_POS + Vector2(6, 0), skin.darkened(0.15), 28.0)
	cv.draw_circle(HAND_POS, 36.0, dark)
	cv.draw_circle(HAND_POS + Vector2(4, -4), 31.0, skin)
	cv.draw_line(HAND_POS, HAND_POS + dir * 60.0, dark, 22.0)
	cv.draw_line(HAND_POS + Vector2(0, -3), HAND_POS + Vector2(0, -3) + dir * 58.0, skin, 15.0)
	# rim light dari bulan (kanan atas)
	cv.draw_arc(HAND_POS + Vector2(4, -4), 31.0, -PI * 0.75, -PI * 0.05, 14, Color(0.85, 0.92, 1.0, 0.55), 3.0)
	var pulse := 0.5 + 0.5 * sin(time * 6.0)
	cv.draw_circle(tip, 22.0 + 4.0 * pulse, Color(0.4, 0.9, 1.0, 0.25))
	cv.draw_circle(tip, 12.0, Color(0.6, 1.0, 1.0, 0.9))
	_text(HAND_POS + Vector2(-60, 14), "TANGAN (placeholder)", 11, Color(0, 0, 0, 0.55), HORIZONTAL_ALIGNMENT_CENTER, 120.0)


func _draw_vfx_world() -> void:
	for p in projectiles:
		var k: float = clampf(p.t / p.dur, 0.0, 1.0)
		var pos: Vector2 = p.origin.lerp(p.dest, k)
		var tail: Vector2 = p.origin.lerp(p.dest, maxf(0.0, k - 0.3))
		cv.draw_line(tail, pos, Color(0.5, 1.0, 1.0, 0.5), 6.0)
		cv.draw_circle(pos, 10.0, Color(0.7, 1.0, 1.0))
	for fx in effects:
		var k: float = clampf(fx.t / fx.dur, 0.0, 1.0)
		if fx.hit:
			var r: float = lerpf(10.0, 55.0, k)
			cv.draw_arc(fx.pos, r, 0.0, TAU, 32, Color(1.0, 0.95, 0.4, 1.0 - k), 5.0)
			for j in 8:
				var a := TAU * float(j) / 8.0
				cv.draw_line(fx.pos + Vector2.from_angle(a) * r * 0.5, fx.pos + Vector2.from_angle(a) * r * 1.1, Color(1, 1, 1, 1.0 - k), 3.0)
		else:
			var r2: float = lerpf(6.0, 28.0, k)
			cv.draw_arc(fx.pos, r2, 0.0, TAU, 24, Color(0.7, 0.9, 1.0, 0.8 * (1.0 - k)), 3.0)
	for s in sparks:
		var k: float = clampf(s.t / s.life, 0.0, 1.0)
		cv.draw_circle(s.pos, 5.0 * (1.0 - k) + 1.0, Color(s.col.r, s.col.g, s.col.b, 1.0 - k))


# ---------------------------------------------------------------- lights (additive)

func _draw_lights() -> void:
	# cahaya bulan
	var moon := MOON_POS + _par_off(5.0)
	_glow(moon, 360.0, Color(0.45, 0.55, 0.85, 0.22))
	_glow(moon, 110.0, Color(0.9, 0.92, 1.0, 0.35))

	# kunang-kunang
	for i in 18:
		var fp := _firefly_pos(i, 20.0 + fmod(float(i), 3.0) * 6.0)
		var blink := clampf(0.5 + 0.8 * sin(time * 2.2 + float(i) * 2.3), 0.0, 1.0)
		_glow(fp, 14.0, Color(0.8, 1.0, 0.55, 0.55 * blink))
		_glow(fp, 3.0, Color(1.0, 1.0, 0.8, 0.9 * blink))

	# mata mahluk berpendar samar dalam gelap
	for c in creatures:
		if c.hit:
			continue
		var d := 1.0 if c.vx >= 0.0 else -1.0
		var eye: Vector2 = c.pos + Vector2(15.0 * d, -8.0) * c.scale
		_glow(eye, 16.0 * c.scale, Color(1.0, 1.0, 0.85, 0.35))

	if state == State.MENU:
		return

	# tangan = sumber cahaya utama (menerangi lengan dan tanah)
	var tip := _hand_tip()
	var pulse := 0.5 + 0.5 * sin(time * 6.0)
	_glow(tip, 70.0 + 8.0 * pulse, Color(0.35, 0.85, 1.0, 0.5))
	_glow(HAND_POS + Vector2(0, -10), 260.0, Color(0.2, 0.55, 0.75, 0.22 + 0.04 * pulse))
	# kilat saat menembak
	if flash > 0.0:
		_glow(tip, 240.0 * flash + 60.0, Color(0.5, 0.95, 1.0, 0.7 * flash))
		cv.draw_rect(Rect2(-60, -60, W + 120, H + 120), Color(0.2, 0.45, 0.55, 0.12 * flash))

	# proyektil menerangi jalurnya
	for p in projectiles:
		var k: float = clampf(p.t / p.dur, 0.0, 1.0)
		_glow(p.origin.lerp(p.dest, k), 70.0, Color(0.5, 1.0, 1.0, 0.6))

	# ledakan: kena = hangat terang, meleset = biru kecil
	for fx in effects:
		var k: float = clampf(fx.t / fx.dur, 0.0, 1.0)
		if fx.hit:
			_glow(fx.pos, lerpf(80.0, 200.0, k), Color(1.0, 0.85, 0.45, 0.75 * (1.0 - k)))
		else:
			_glow(fx.pos, lerpf(30.0, 70.0, k), Color(0.5, 0.8, 1.0, 0.45 * (1.0 - k)))
	for s in sparks:
		var k: float = clampf(s.t / s.life, 0.0, 1.0)
		_glow(s.pos, 16.0, Color(s.col.r, s.col.g, s.col.b, 0.6 * (1.0 - k)))


# ---------------------------------------------------------------- UI (tidak ikut digelapkan)

func _draw_ui() -> void:
	if state == State.MENU:
		_draw_menu()
		_draw_crosshair()
		return

	if state == State.PLAY and hunger <= 0.01:
		var a := 0.2 + 0.12 * sin(time * 5.0)
		cv.draw_rect(Rect2(0, 0, W, H), Color(0.8, 0.0, 0.0, a), false, 48.0)

	_draw_hud()
	if state == State.PLAY and banner_t > 0.0:
		var ba := clampf(banner_t / 0.5, 0.0, 1.0)
		_text(Vector2(0, 300), "LEVEL %d" % (level + 1), 90, Color(1, 1, 1, ba), HORIZONTAL_ALIGNMENT_CENTER, W)
		_text(Vector2(0, 345), "dari %d" % LEVELS.size(), 26, Color(1, 1, 1, 0.8 * ba), HORIZONTAL_ALIGNMENT_CENTER, W)
	for f in floaters:
		_text(f.pos, f.text, 32, Color(f.col.r, f.col.g, f.col.b, 1.0 - f.t / 0.9), HORIZONTAL_ALIGNMENT_CENTER, 100.0)

	if state == State.TUTORIAL:
		_draw_tutorial()
	elif state == State.END:
		_draw_end()

	_draw_crosshair()


func _draw_hud() -> void:
	# --- bar lapar (bergetar saat hampir kosong)
	var jx := 0.0
	if state == State.PLAY and hunger <= 2.0:
		jx = sin(time * 45.0) * 1.5
	cv.draw_rect(Rect2(24, 16, 440, 78), Color(0, 0, 0, 0.45))
	_text(Vector2(40, 42), "LAPAR", 20, Color.WHITE)
	var bar_col := Color.from_hsv(0.33 * (hunger / MAX_HUNGER), 0.8, 0.95)
	for i in 10:
		var r := Rect2(40 + i * 40 + jx, 52, 36, 28)
		cv.draw_rect(r, Color(0.1, 0.1, 0.12))
		var fill := clampf(hunger - float(i), 0.0, 1.0)
		if fill > 0.0:
			cv.draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), bar_col)
		cv.draw_rect(r, Color(1, 1, 1, 0.8), false, 2.0)

	# --- level
	cv.draw_rect(Rect2(540, 16, 200, 78), Color(0, 0, 0, 0.45))
	_text(Vector2(540, 42), "LEVEL", 20, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	for i in LEVELS.size():
		var pc := Vector2(590 + i * 25, 68)
		if i < level:
			cv.draw_circle(pc, 8.0, Color(0.5, 1.0, 0.6))
		elif i == level:
			cv.draw_circle(pc, 10.0, Color(1.0, 0.9, 0.3))
		else:
			cv.draw_arc(pc, 8.0, 0.0, TAU, 16, Color(1, 1, 1, 0.4), 2.0)

	# --- tenaga (peluru)
	cv.draw_rect(Rect2(916, 16, 340, 78), Color(0, 0, 0, 0.45))
	_text(Vector2(936, 42), "TENAGA", 20, Color.WHITE)
	for i in MAX_BULLETS:
		var ctr := Vector2(956 + i * 52, 68)
		if i < bullets:
			cv.draw_circle(ctr, 17.0, Color(0.4, 0.9, 1.0, 0.3))
			cv.draw_circle(ctr, 12.0, Color(0.6, 1.0, 1.0))
		else:
			cv.draw_arc(ctr, 12.0, 0.0, TAU, 20, Color(1, 1, 1, 0.35), 2.0)

	if state == State.PLAY:
		_draw_comment()


func _draw_comment() -> void:
	if comment_t <= 0.0:
		return
	var expr := 0
	if comment_total - comment_t < 0.8:
		expr = 1
	elif comment_pos:
		expr = 2
	_draw_narrator(Vector2(110, 700), 0.55, expr)
	cv.draw_style_box(bubble_style, Rect2(190, 596, 400, 60))
	_text(Vector2(190, 633), comment_text, 20, Color(0.15, 0.1, 0.05), HORIZONTAL_ALIGNMENT_CENTER, 400.0)


func _highlight_rect() -> Rect2:
	match TUTORIAL_STEPS[tut_step]["hl"]:
		"hunger":
			return Rect2(24, 16, 440, 78)
		"bullets":
			return Rect2(916, 16, 340, 78)
		"hand":
			return Rect2(560, 625, 160, 95)
		"creature":
			for c in creatures:
				if not c.hit and c.pos.x > 40.0 and c.pos.x < W - 40.0:
					return Rect2(c.pos - Vector2(60, 55), Vector2(120, 110))
	return Rect2()


func _draw_dim(hole: Rect2) -> void:
	var col := Color(0, 0, 0, 0.62)
	cv.draw_rect(Rect2(0, 0, W, hole.position.y), col)
	cv.draw_rect(Rect2(0, hole.end.y, W, H - hole.end.y), col)
	cv.draw_rect(Rect2(0, hole.position.y, hole.position.x, hole.size.y), col)
	cv.draw_rect(Rect2(hole.end.x, hole.position.y, W - hole.end.x, hole.size.y), col)
	var pulse := 0.5 + 0.5 * sin(time * 6.0)
	cv.draw_rect(hole.grow(4.0), Color(1.0, 0.9, 0.2, 0.6 + 0.4 * pulse), false, 4.0)


func _draw_tutorial() -> void:
	var hole := _highlight_rect()
	if hole.size.x > 0.0:
		_draw_dim(hole)
	var last := tut_step == TUTORIAL_STEPS.size() - 1
	var expr := 0
	if not _typing_done():
		expr = 1
	elif last:
		expr = 2
	_draw_narrator(Vector2(180, 610), 1.0, expr)
	cv.draw_style_box(panel_style, Rect2(320, 380, 640, 230))
	_text(Vector2(345, 412), "NARATOR", 18, Color(0.5, 0.25, 0.1))
	_text(Vector2(345, 592), "%d / %d" % [tut_step + 1, TUTORIAL_STEPS.size()], 16, Color(0.35, 0.2, 0.1, 0.7))
	if _typing_done():
		var blink := 0.6 + 0.4 * sin(time * 5.0)
		_text(Vector2(700, 592), "klik untuk lanjut >", 16, Color(0.35, 0.2, 0.1, blink), HORIZONTAL_ALIGNMENT_RIGHT, 240.0)


## expr: 0 = Neutral/Idle, 1 = Talking, 2 = Resonant
func _draw_narrator(origin: Vector2, s: float, expr: int) -> void:
	var ink := Color(0.5, 0.1, 0.1)
	cv.draw_set_transform(origin, 0.0, Vector2(s, s))
	cv.draw_rect(Rect2(-70, -120, 140, 120), Color(0.25, 0.45, 0.55))
	cv.draw_circle(Vector2(0, -170), 52.0, Color(0.96, 0.8, 0.65))
	cv.draw_circle(Vector2(-18, -180), 6.0, Color.BLACK)
	cv.draw_circle(Vector2(18, -180), 6.0, Color.BLACK)
	var mouth := Vector2(0, -150)
	match expr:
		1:
			cv.draw_circle(mouth, 5.0 + 4.0 * absf(sin(time * 12.0)), ink)
		2:
			cv.draw_arc(mouth + Vector2(0, -8), 18.0, 0.3, PI - 0.3, 12, ink, 3.0)
		_:
			cv.draw_line(mouth + Vector2(-12, 0), mouth + Vector2(12, 0), ink, 3.0)
	cv.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if s >= 0.99:
		_text(origin + Vector2(-80, 26), "Narator (placeholder)", 13, Color(1, 1, 1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 160.0)


func _draw_menu() -> void:
	_text(Vector2(0, 220), "STRANDED", 110, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W)
	_text(Vector2(0, 270), "Berburu atau diburu.", 26, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER, W)
	_button(Rect2(490, 320, 300, 64), "MULAI")
	_button(Rect2(490, 400, 300, 64), "ABOUT")
	_button(Rect2(490, 480, 300, 64), "KELUAR")
	_text(Vector2(0, 690), "Portfolio #2", 16, Color(1, 1, 1, 0.55), HORIZONTAL_ALIGNMENT_CENTER, W)
	if show_about:
		cv.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.7))
		cv.draw_style_box(panel_style, Rect2(290, 260, 700, 200))
		_text(Vector2(290, 330), "ABOUT", 26, Color(0.5, 0.25, 0.1), HORIZONTAL_ALIGNMENT_CENTER, 700.0)
		_text(Vector2(290, 385), "Created By Ananda Aghi For Final College Project", 26, Color(0.15, 0.1, 0.05), HORIZONTAL_ALIGNMENT_CENTER, 700.0)
		_text(Vector2(290, 440), "klik di mana saja untuk menutup", 15, Color(0.35, 0.2, 0.1, 0.7), HORIZONTAL_ALIGNMENT_CENTER, 700.0)


func _draw_end() -> void:
	cv.draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.6))
	var epilog := end_step < end_lines.size()
	var title := "KENYANG!" if won else "MATI KELAPARAN"
	if won and not _final_level():
		title = "LEVEL %d SELESAI!" % (level + 1)
	var tcol := Color(0.5, 1.0, 0.6) if won else Color(1.0, 0.4, 0.4)
	_text(Vector2(0, 250.0 if epilog else 290.0), title, 80, tcol, HORIZONTAL_ALIGNMENT_CENTER, W)

	if epilog:
		var expr := 0
		if not _typing_done():
			expr = 1
		elif won and end_step == end_lines.size() - 1:
			expr = 2
		_draw_narrator(Vector2(180, 610), 1.0, expr)
		cv.draw_style_box(panel_style, Rect2(320, 380, 640, 230))
		_text(Vector2(345, 412), "NARATOR", 18, Color(0.5, 0.25, 0.1))
		if _typing_done():
			var blink := 0.6 + 0.4 * sin(time * 5.0)
			_text(Vector2(700, 592), "klik untuk lanjut >", 16, Color(0.35, 0.2, 0.1, blink), HORIZONTAL_ALIGNMENT_RIGHT, 240.0)
	else:
		var stats := "Kelima level selesai!" if won else "Gagal di Level %d. Tenaga habis sebelum bar lapar penuh." % (level + 1)
		_text(Vector2(0, 350), stats, 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W)
		_button(Rect2(400, 440, 220, 70), "MAIN LAGI" if won else "COBA LAGI")
		_button(Rect2(660, 440, 220, 70), "MENU")
		_text(Vector2(0, 580), "Terima kasih sudah bermain.", 22, Color(1, 1, 1, 0.6), HORIZONTAL_ALIGNMENT_CENTER, W)


func _draw_crosshair() -> void:
	var col := Color(1, 1, 1, 0.95)
	cv.draw_arc(mouse, 18.0, 0.0, TAU, 32, col, 2.5)
	cv.draw_line(mouse + Vector2(-28, 0), mouse + Vector2(-8, 0), col, 2.5)
	cv.draw_line(mouse + Vector2(8, 0), mouse + Vector2(28, 0), col, 2.5)
	cv.draw_line(mouse + Vector2(0, -28), mouse + Vector2(0, -8), col, 2.5)
	cv.draw_line(mouse + Vector2(0, 8), mouse + Vector2(0, 28), col, 2.5)
	cv.draw_circle(mouse, 2.5, Color(1, 0.3, 0.3))
