class_name StartScreen
extends Control
## First thing the player sees. The reef is visible straight away.

signal play_pressed
signal reef_pressed

var session: GameSession
var reef: ReefView
var chip_coins: HudWidgets.Chip
var chip_pearls: HudWidgets.Chip
var chip_res: HudWidgets.Chip
var btn_play: PillButton
var btn_motion: PillButton
var btn_sound: PillButton
var info_label: Label
var title_label: Label
var sfx: Sfx

func setup(s: GameSession, audio: Sfx) -> void:
	session = s
	sfx = audio
	title_label = Label.new()
	title_label.text = "Tidepool Tycoon"
	title_label.add_theme_font_size_override("font_size", 44)
	title_label.add_theme_color_override("font_color", Pal.TEXT)
	title_label.add_theme_color_override("font_outline_color", Pal.INK)
	title_label.add_theme_constant_override("outline_size", 8)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)
	reef = ReefView.new()
	reef.caption = "Your reef"
	add_child(reef)
	reef.tapped.connect(func() -> void: reef_pressed.emit())
	chip_coins = _chip("coin", "Coins", Pal.GOLD)
	chip_pearls = _chip("pearl", "Pearls", Color("bcdcff"))
	chip_res = _chip("reef", "Residents", Pal.TEAL)
	btn_play = PillButton.new()
	btn_play.accent = Pal.TEAL
	btn_play.font_size = 26
	btn_play.icon = "wave"
	add_child(btn_play)
	btn_play.pressed.connect(func() -> void: play_pressed.emit())
	btn_motion = PillButton.new()
	btn_motion.accent = Pal.TEXT_DIM
	btn_motion.font_size = 17
	add_child(btn_motion)
	btn_motion.pressed.connect(func() -> void:
		session.set_setting("reduced_motion", not bool(session.profile.settings.get("reduced_motion", false)))
		refresh())
	btn_sound = PillButton.new()
	btn_sound.accent = Pal.TEXT_DIM
	btn_sound.font_size = 17
	add_child(btn_sound)
	btn_sound.pressed.connect(func() -> void:
		session.set_setting("sound", not bool(session.profile.settings.get("sound", true)))
		refresh())
	info_label = Label.new()
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.add_theme_color_override("font_color", Pal.TEXT_DIM)
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(info_label)
	resized.connect(_layout)

func _chip(icon: String, label: String, accent: Color) -> HudWidgets.Chip:
	var c := HudWidgets.Chip.new()
	c.icon = icon
	c.label = label
	c.accent = accent
	add_child(c)
	return c

func _layout() -> void:
	if reef == null:
		return
	var w: float = size.x
	var h: float = size.y
	var cw: float = minf(w, 540.0)
	var x0: float = (w - cw) * 0.5 + 12.0
	var iw: float = cw - 24.0
	title_label.position = Vector2(x0, 22)
	title_label.size = Vector2(iw, 60)
	var y: float = 96.0
	var chip_w: float = (iw - 12.0) / 3.0
	for i in 3:
		var c: HudWidgets.Chip = [chip_coins, chip_pearls, chip_res][i]
		c.position = Vector2(x0 + float(i) * (chip_w + 6.0), y)
		c.size = Vector2(chip_w, 52)
	y += 52.0 + 12.0
	var reef_h: float = maxf(220.0, h - y - 250.0)
	reef.position = Vector2(x0, y)
	reef.size = Vector2(iw, reef_h)
	y += reef_h + 14.0
	info_label.position = Vector2(x0, y)
	info_label.size = Vector2(iw, 50)
	y += 56.0
	btn_play.position = Vector2(x0, y)
	btn_play.size = Vector2(iw, 64)
	y += 64.0 + 10.0
	btn_motion.position = Vector2(x0, y)
	btn_motion.size = Vector2((iw - 8.0) * 0.5, 44)
	btn_sound.position = Vector2(x0 + (iw + 8.0) * 0.5, y)
	btn_sound.size = Vector2((iw - 8.0) * 0.5, 44)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or (what == NOTIFICATION_VISIBILITY_CHANGED and visible):
		_layout()

func refresh() -> void:
	_layout()
	var p: Profile = session.profile
	chip_coins.value = PoolScreen.fmt_hud(p.coins)
	chip_pearls.value = PoolScreen.fmt_hud(p.pearls)
	chip_res.value = str(p.residents.size())
	reef.set_residents(p.residents)
	var rm: bool = bool(p.settings.get("reduced_motion", false))
	reef.reduced_motion = rm
	btn_motion.text = "Reduced motion: %s" % ("ON" if rm else "off")
	btn_motion.toggled = rm
	var snd: bool = bool(p.settings.get("sound", true))
	btn_sound.text = "Sound: %s" % ("on" if snd else "OFF")
	btn_sound.toggled = not snd
	if sfx != null:
		sfx.enabled = snd
	var run: RunState = session.run
	if run == null:
		btn_play.text = "Dive in"
		info_label.text = "Merge creatures, ride the Currents, and release your best into the reef."
	elif run.status == RunState.FLOODED:
		btn_play.text = "See run summary"
		info_label.text = "The last pool flooded. Release survivors and start a new run."
	else:
		btn_play.text = "Resume run"
		info_label.text = "Run %d in progress · turn %d · %d creatures in the pool" % [run.run_number, run.turn, run.board.creature_count()]
