extends SceneTree
## Contact sheet of the reef and pool backgrounds for all four tide phases, plus a 1:1 board close-up.
##   xvfb-run -a -s "-screen 0 1200x1000x24" $GODOT --rendering-driver opengl3 --path . --script res://dev/bg_sheet.gd
## Optional: BG_PARTS=/some/dir also writes per-part crops (reef_N / pool_N / board_N .png) for 1:1 inspection.

const CELL_W := 540
const REEF := Vector2(520, 340)
const POOL_SCALE := 0.5
const GRID := Rect2(10, 184, 422, 488)     # 26px tab margin + 6x7 cells of 66px
const CS := 66.0
const T := 6.5

class P extends Control:
	var kind: String = "reef"
	var phase: int = 1

	func _label(p: Vector2, s: String) -> void:
		draw_string(ThemeDB.fallback_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	func _chip(r: Rect2, text: String) -> void:
		draw_style_box(_sb(Pal.SAND, 16), r)
		draw_string(ThemeDB.fallback_font, r.position + Vector2(14, r.size.y * 0.5 + 6), text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 20, 17, Pal.INK)

	func _panel(r: Rect2, col: Color) -> void:
		draw_style_box(_sb(col, 14), r)

	func _sb(col: Color, rad: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = col
		s.set_corner_radius_all(rad)
		s.anti_aliasing = true
		return s

	func _board(pal: Dictionary) -> void:
		BgArt.draw_board_frame(self, GRID, pal)
		for i in 42:
			var r: int = i / 6
			var c: int = i % 6
			var rc := Rect2(GRID.position + Vector2(26, 26) + Vector2(c, r) * CS, Vector2(CS, CS)).grow(-2.0)
			var occ: bool = ((i * 7 + 3) % 5) != 0 and (i % 11) != 4
			BgArt.draw_tile(self, rc, r + c, occ, pal)
			if occ and (i * 13 + 5) % 4 != 0:
				var tier: int = 1 + (i * 5) % 6
				var col: Color = Pal.tier_color(tier)
				var ctr: Vector2 = rc.get_center()
				draw_circle(ctr, 22.0, col.darkened(0.25))
				draw_circle(ctr + Vector2(-1, -2), 19.0, col)
				draw_circle(ctr + Vector2(-7, -8), 5.0, Color(1, 1, 1, 0.45))
		# tabs (arrow chips) like BoardView
		for i in 7:
			var rr := Rect2(GRID.position + Vector2(1, 26 + i * CS + 3), Vector2(22, CS - 6))
			draw_style_box(_sb(Color(Pal.TEXT_DIM.darkened(0.45), 0.14), 6), rr)
		for i in 6:
			var rr2 := Rect2(GRID.position + Vector2(26 + i * CS + 3, 1), Vector2(CS - 6, 22))
			draw_style_box(_sb(Color(Pal.TEXT_DIM.darkened(0.45), 0.14), 6), rr2)

	func _pool(pal: Dictionary, mock: bool) -> void:
		var rect := Rect2(0, 0, 540, 960)
		BgArt.draw_pool_backdrop_static(self, rect, GRID, pal)
		BgArt.draw_pool_backdrop_anim(self, rect, GRID, pal, T, true)
		if not mock:
			return
		# HUD mock: chips, floating text on the bare backdrop, surge strip
		_chip(Rect2(10, 8, 150, 48), "Coins 1,240")
		_chip(Rect2(170, 8, 150, 48), "Pearls 12")
		_panel(Rect2(330, 12, 92, 40), Color(0.02, 0.15, 0.2, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(346, 38), "Reef", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Pal.TEXT)
		_chip(Rect2(10, 64, 255, 48), "Turn 14")
		_chip(Rect2(275, 64, 255, 48), "Currents 2")
		_panel(Rect2(10, 120, 520, 52), Color(0.02, 0.15, 0.2, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(24, 152), "Surge in 3 turns", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Pal.TEXT)
		draw_string(ThemeDB.fallback_font, Vector2(440, 38), "Floating text 22", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.TEXT)
		_board(pal)
		_panel(Rect2(442, 210, 88, 462), Color(0.02, 0.15, 0.2, 0.55))
		_panel(Rect2(10, 696, 520, 58), Color(0.02, 0.15, 0.2, 0.7))
		draw_string(ThemeDB.fallback_font, Vector2(26, 732), "Tap a creature to select it.", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Pal.TEXT)
		for k in 4:
			_panel(Rect2(10 + k * 132, 762, 124, 54), Color(Pal.CORAL.r, Pal.CORAL.g, Pal.CORAL.b, 0.9))
		_panel(Rect2(10, 824, 520, 96), Color(0.02, 0.15, 0.2, 0.5))

	func _draw() -> void:
		var pal: Dictionary = BgArt.palette(phase)
		match kind:
			"reef":
				var r := Rect2(Vector2.ZERO, REEF)
				BgArt.draw_reef_far(self, r, pal)
				BgArt.draw_reef_mid(self, r, pal)
				BgArt.draw_reef_front(self, r, pal, T, true)
			"pool":
				_pool(pal, true)
			"bare":
				_pool(pal, false)
			"board":
				draw_set_transform(Vector2(0, -164), 0.0, Vector2.ONE)
				_pool(pal, false)
				_board(pal)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _initialize() -> void:
	var cols: int = 2
	var cell_h: int = int(REEF.y) + 8 + int(960.0 * POOL_SCALE) + 20
	var board_sz := Vector2(450, 530)
	var top_h: int = cell_h * 2
	var bare_h: int = int(960.0 * POOL_SCALE) + 10
	var total := Vector2i(maxi(CELL_W * cols, 1100), top_h + int(board_sz.y + 10) * 2 + bare_h)
	var vp := SubViewport.new()
	vp.size = total
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color("20262c")
	bg.size = Vector2(total)
	vp.add_child(bg)
	var parts: Array = []
	for ph in 4:
		var cx: int = (ph % 2) * CELL_W
		var cy: int = (ph / 2) * cell_h
		var reef := P.new()
		reef.kind = "reef"
		reef.phase = ph
		reef.size = REEF
		reef.clip_contents = true
		reef.position = Vector2(cx + 10, cy + 4)
		vp.add_child(reef)
		var pool := P.new()
		pool.kind = "pool"
		pool.phase = ph
		pool.size = Vector2(540, 960)
		pool.scale = Vector2(POOL_SCALE, POOL_SCALE)
		pool.clip_contents = true
		pool.position = Vector2(cx + 10, cy + REEF.y + 12)
		vp.add_child(pool)
		var lb := Label.new()
		lb.text = "%s  (reef 1:1 above, pool at 50%%)" % Tide.phase_name(ph)
		lb.position = Vector2(cx + 290, cy + REEF.y + 16)
		vp.add_child(lb)
		var board := P.new()
		board.kind = "board"
		board.phase = ph
		board.size = board_sz
		board.clip_contents = true
		board.position = Vector2((ph % 2) * (board_sz.x + 20) + 10, top_h + (ph / 2) * (board_sz.y + 10) + 4)
		vp.add_child(board)
		var bare := P.new()
		bare.kind = "bare"
		bare.phase = ph
		bare.size = Vector2(540, 960)
		bare.scale = Vector2(POOL_SCALE, POOL_SCALE)
		bare.clip_contents = true
		bare.position = Vector2(10 + ph * 272, top_h + int(board_sz.y + 10) * 2 + 4)
		vp.add_child(bare)
		parts.append([reef, pool, board, bare])
	root.add_child(vp)
	for i in 6:
		await process_frame
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://dev/out"))
	img.save_png("res://dev/out/bg_sheet.png")
	var dir: String = OS.get_environment("BG_PARTS")
	if dir != "":
		DirAccess.make_dir_recursive_absolute(dir)
		for ph in 4:
			var pp: Array = parts[ph]
			for k in 4:
				var c: Control = pp[k]
				var sz: Vector2 = c.size * c.scale
				var crop: Image = img.get_region(Rect2i(Vector2i(c.position), Vector2i(sz)))
				crop.save_png("%s/%s_%d.png" % [dir, ["reef", "pool", "board", "bare"][k], ph])
	print("bg sheet written")
	quit()
