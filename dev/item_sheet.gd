extends SceneTree
## Contact sheet for ItemArt + DecorArt -> res://dev/out/item_sheet.png (+ item_sheet_N.png crops,
## 1:1 horizontal bands of 800px for close inspection).
##   GODOT=/tmp/claude-0/godot_dl/Godot_v4.3-stable_linux.x86_64
##   xvfb-run -a -s "-screen 0 1200x900x24" $GODOT --rendering-driver opengl3 --path . --script res://dev/item_sheet.gd

const W := 1600
const H := 2640
const BAND := 800
const T := 1.3

class Sheet extends Control:
	func _water(r: Rect2, night: float = 0.0, sand: float = 0.0) -> void:
		var top: Color = Pal.BG_TOP.lerp(Color("0a1f3d"), night)
		var bot: Color = Pal.BG_BOTTOM.lerp(Color("050f22"), night)
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([top, top, bot, bot]))
		if sand > 0.0:
			var sy: float = r.end.y - r.size.y * sand
			draw_rect(Rect2(r.position.x, sy, r.size.x, r.size.y * sand), Pal.SAND_DARK.lerp(Color("4a4a62"), night * 0.6))
			draw_rect(Rect2(r.position.x, sy, r.size.x, 3.0), Pal.SAND.lerp(Color("7c7a96"), night * 0.6))

	func _label(p: Vector2, s: String, fs: int = 12) -> void:
		draw_string(ThemeDB.fallback_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Pal.TEXT)

	func _title(y: float, s: String) -> void:
		draw_rect(Rect2(0, y, W, 26), Color(0, 0, 0, 0.35))
		draw_string(ThemeDB.fallback_font, Vector2(12, y + 18), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.GOLD)

	const STATES := ["available", "selected", "locked", "unaffordable", "owned"]

	func _draw() -> void:
		draw_rect(Rect2(0, 0, W, H), Color("0c5568"))
		var y: float = 0.0
		# ------------------------------------------------ coins / pearls
		_title(y, "COIN + PEARL: 5 states at 80px and 28px (and 160px detail)")
		for i in 5:
			var cx: float = 70.0 + float(i) * 150.0
			ItemArt.draw_coin(self, Vector2(cx, y + 80.0), 80.0, i, {"t": T})
			ItemArt.draw_coin(self, Vector2(cx - 30.0, y + 160.0), 28.0, i)
			ItemArt.draw_pearl(self, Vector2(cx + 760.0, y + 80.0), 80.0, i, {"t": T})
			ItemArt.draw_pearl(self, Vector2(cx + 730.0, y + 160.0), 28.0, i)
			ItemArt.draw_pearl(self, Vector2(cx + 790.0, y + 160.0), 40.0, i)
			_label(Vector2(cx - 30.0, y + 190.0), STATES[i])
		y += 210.0
		# ------------------------------------------------ current token + chest
		_title(y, "CURRENT TOKEN (charges 3 / selected 3 / spent 0 / locked) and CHEST (closed / full / open)")
		y += 30.0
		var tk := Rect2(20, y + 20, 120, 70)
		ItemArt.draw_current_token(self, tk, 3, 0, T)
		ItemArt.draw_current_token(self, Rect2(160, y + 20, 120, 70), 3, 1, T)
		ItemArt.draw_current_token(self, Rect2(300, y + 20, 120, 70), 0, 0, T)
		ItemArt.draw_current_token(self, Rect2(440, y + 20, 120, 70), 3, 2, T)
		ItemArt.draw_current_token(self, Rect2(20, y + 120, 56, 56), 2, 0, T)
		ItemArt.draw_current_token(self, Rect2(100, y + 120, 56, 56), 2, 1, T)
		ItemArt.draw_current_token(self, Rect2(180, y + 120, 56, 56), 0, 0, T)
		ItemArt.draw_current_token(self, Rect2(260, y + 120, 56, 56), 1, 2, T)
		ItemArt.draw_current_token(self, Rect2(340, y + 100, 220, 100), 5, 1, T)
		_label(Vector2(20, y + 215), "available  /  selected  /  spent  /  locked")
		for i in 3:
			ItemArt.draw_chest(self, Rect2(620 + i * 230, y + 10, 210, 200), i, T)
		ItemArt.draw_chest(self, Rect2(1320, y + 10, 64, 62), 0, T)
		ItemArt.draw_chest(self, Rect2(1320, y + 90, 64, 62), 1, T)
		ItemArt.draw_chest(self, Rect2(1320, y + 160, 64, 62), 2, T)
		y += 240.0
		# ------------------------------------------------ reef gate
		_title(y, "REEF GATE: 84x470 (available / selected / locked) beside 170x940 (same states)")
		y += 30.0
		for i in 3:
			var st: int = [0, 1, 2][i]
			var gx: float = 20.0 + float(i) * 110.0
			_water(Rect2(gx - 6, y, 96, 470))
			ItemArt.draw_reef_gate(self, Rect2(gx, y, 84, 470), st, T, 5)
			draw_circle(Vector2(gx + 42, y + 470 - 30), 17.0, Pal.INK)
			_label(Vector2(gx + 8, y + 486), STATES[st])
		for i in 3:
			var st2: int = [0, 1, 2][i]
			var gx2: float = 380.0 + float(i) * 200.0
			_water(Rect2(gx2 - 6, y, 182, 940))
			ItemArt.draw_reef_gate(self, Rect2(gx2, y, 170, 940), st2, T, 5)
			_label(Vector2(gx2 + 40, y + 956), STATES[st2])
		# card frames beside the large gates
		_title(y, "")
		var cy: float = y + 10.0
		draw_string(ThemeDB.fallback_font, Vector2(1000, cy + 12), "CARD FRAMES (+ DecorArt thumbnail)", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Pal.GOLD)
		for i in 5:
			var cr := Rect2(1000, cy + 24.0 + float(i) * 112.0, 330, 96)
			ItemArt.draw_card_frame(self, cr, i, {"t": T})
			var kind: int = i
			var th := Rect2(cr.position.x + 12, cr.position.y + 10, 60, 78)
			_water(th, 0.0, 0.25)
			DecorArt.draw(self, kind, th, T, {"state": i if i != 1 else 0})
			var fc: Color = Pal.INK if i != 2 else Color("cfe3ea")
			draw_string(ThemeDB.fallback_font, cr.position + Vector2(84, 34), GameConfig.DECORATIONS[kind]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, fc)
			draw_string(ThemeDB.fallback_font, cr.position + Vector2(84, 54), STATES[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fc)
			ItemArt.draw_coin(self, cr.position + Vector2(98, 74), 22.0, 0 if i != 3 else 3)
			draw_string(ThemeDB.fallback_font, cr.position + Vector2(114, 80), str(GameConfig.DECORATIONS[kind]["price"]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, fc)
		# ------------------------------------------------ decorations (right of gates) -> next band
		y += 980.0
		_title(y, "DECOR: 56x73, 120x156, 200x260 on water (top) and on sand (bottom)")
		y += 30.0
		for kind in 5:
			var bx: float = 10.0 + float(kind) * 316.0
			var big := Rect2(bx, y, 220, 280)
			_water(big, 0.0, 0.12)
			DecorArt.draw(self, kind, Rect2(bx + 10, y + 10, 200, 260), T, {})
			var mid := Rect2(bx + 226, y, 76, 140)
			_water(mid, 0.0, 0.0)
			DecorArt.draw(self, kind, Rect2(mid.position.x + 2, mid.position.y + 4, 72, 94), T, {})
			var small := Rect2(bx + 226, y + 142, 76, 138)
			_water(small, 0.0, 0.3)
			DecorArt.draw(self, kind, Rect2(small.position.x + 10, small.end.y - 8 - 73, 56, 73), T, {})
		y += 290.0
		# 120x156 on both backgrounds + states
		for kind in 5:
			var bx2: float = 10.0 + float(kind) * 316.0
			var a := Rect2(bx2, y, 140, 170)
			_water(a, 0.0, 0.1)
			DecorArt.draw(self, kind, Rect2(a.position.x + 10, a.end.y - 160, 120, 156), T, {})
			var b := Rect2(bx2 + 148, y, 160, 170)
			draw_rect(b, Pal.SAND)
			draw_rect(Rect2(b.position.x, b.end.y - 14, b.size.x, 14), Pal.SAND_DARK)
			DecorArt.draw(self, kind, Rect2(b.position.x + 4, b.end.y - 14 - 70 * 1.3 + 8, 70, 91), T, {})
			DecorArt.draw(self, kind, Rect2(b.position.x + 82, b.end.y - 14 - 70 * 1.3 + 8, 70, 91), T, {"state": 2})
		y += 180.0
		_label(Vector2(10, y + 10), "states per kind: locked / unaffordable / owned / selected / alpha-0.5 still ghost")
		for kind in 5:
			var bx3: float = 10.0 + float(kind) * 316.0
			var sts: Array = [2, 3, 4, 1, 0]
			for si in 5:
				var rr := Rect2(bx3 + float(si) * 62.0, y + 16, 60, 110)
				_water(rr, 0.0, 0.1)
				var o: Dictionary = {"state": sts[si]}
				if si == 4:
					o = {"state": 0, "alpha": 0.5, "animate": false}
				DecorArt.draw(self, kind, Rect2(rr.position.x + 2, rr.end.y - 5 - 73, 56, 73), T, o)
		y += 170.0
		# ------------------------------------------------ world effects
		_title(y, "WORLD EFFECTS 300x200 (top row day, bottom row night=1)")
		y += 30.0
		for row in 2:
			for kind in 5:
				var pr := Rect2(8.0 + float(kind) * 316.0, y + float(row) * 212.0, 300, 200)
				_water(pr, float(row), 0.28)
				var slot := Rect2(pr.position.x + 110.0, pr.end.y - 56.0 - 78.0 + 10.0, 60, 78)
				DecorArt.world_effect(self, kind, slot, pr, T, float(row))
				DecorArt.draw(self, kind, slot, T, {})
				_label(pr.position + Vector2(6, 14), GameConfig.DECORATIONS[kind]["name"] + (" night" if row == 1 else " day"))

func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var art := Sheet.new()
	art.size = Vector2(W, H)
	vp.add_child(art)
	root.add_child(vp)
	for i in 6:
		await process_frame
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://dev/out"))
	img.save_png("res://dev/out/item_sheet.png")
	var n: int = 0
	var yy: int = 0
	while yy < H:
		var band: Image = img.get_region(Rect2i(0, yy, W, mini(BAND, H - yy)))
		band.save_png("res://dev/out/item_sheet_%d.png" % n)
		n += 1
		yy += BAND
	print("item sheet written")
	quit()
