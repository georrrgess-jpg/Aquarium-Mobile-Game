extends SceneTree
## Creature contact sheet -> res://dev/out/creature_sheet.png
##   xvfb-run -a -s "-screen 0 1200x900x24" $GODOT --rendering-driver opengl3 --path . --script res://dev/art_sheet.gd
## Rows: Shrimp T1-6, Starfish T1-6, Lantern Ray T4-6. Each column shows a creature at
## 220px (no badge), 110px, and exactly as on the board: 64px on a CELL tile with badge+ring.
## Bottom strips: all 12 board creatures at 64px on tiles (normal + flipped).
## Optional user arg "ray_all" also shows ray T1-T3.

const COL_W := 236.0
const W := 1440
const ROW_H := 470.0
const H := 3 * 470 + 190

class Sheet extends Control:
	func _bg(r: Rect2) -> void:
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Pal.BG_TOP, Pal.BG_TOP, Pal.BG_BOTTOM, Pal.BG_BOTTOM]))

	func _label(p: Vector2, s: String) -> void:
		draw_string(ThemeDB.fallback_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Pal.TEXT)

	func _tile(c: Vector2, s: float, code: int, opts: Dictionary) -> void:
		var r := Rect2(c - Vector2(s, s) * 0.5 - Vector2(1, 1), Vector2(s + 2.0, s + 2.0))
		draw_rect(r, Pal.CELL)
		draw_rect(Rect2(r.position + Vector2(1, 1), r.size - Vector2(2, 2)), Pal.CELL_ALT if (int(c.x / 64.0) + int(c.y / 64.0)) % 2 == 1 else Pal.CELL)
		CreatureArt.draw_creature(self, code, c, s, opts)

	func _draw() -> void:
		_bg(Rect2(0, 0, W, H))
		var rows: Array = [[1, [1, 2, 3, 4, 5, 6]], [2, [1, 2, 3, 4, 5, 6]], [3, [4, 5, 6]]]
		var ray_all: bool = OS.get_cmdline_user_args().has("ray_all")
		if ray_all:
			rows[2] = [3, [1, 2, 3, 4, 5, 6]]
		var phase: float = 0.8
		for ri in rows.size():
			var fam: int = rows[ri][0]
			var tiers: Array = rows[ri][1]
			var y0: float = float(ri) * ROW_H
			# sand strip under the 220 + 110 creatures
			draw_rect(Rect2(0, y0 + 230.0, W, 120.0), Pal.SAND_DARK)
			draw_rect(Rect2(0, y0 + 230.0, W, 3), Pal.SAND)
			for i in tiers.size():
				var tier: int = tiers[i]
				var code: int = Creature.make(fam, tier)
				var cx: float = 12.0 + COL_W * 0.5 + float(i) * COL_W
				_label(Vector2(cx - 40, y0 + 14), "%s  T%d" % [Creature.FAMILY_NAMES[fam], tier])
				CreatureArt.draw_creature(self, code, Vector2(cx, y0 + 134.0), 220.0, {"phase": phase, "badge": false, "glow": false})
				CreatureArt.draw_creature(self, code, Vector2(cx - 54, y0 + 290.0), 110.0, {"phase": phase, "badge": false})
				CreatureArt.draw_creature(self, code, Vector2(cx + 54, y0 + 290.0), 110.0, {"phase": phase, "flip": true, "badge": false})
				_tile(Vector2(cx - 40, y0 + 400.0), 64.0, code, {"phase": phase})
				CreatureArt.draw_creature(self, code, Vector2(cx + 40, y0 + 400.0), 44.0, {"phase": phase, "badge": false, "glow": false})
		# board strip
		var sy: float = 3.0 * ROW_H + 10.0
		_label(Vector2(12, sy), "board strip: 64px tiles (T1-6 shrimp, T1-6 starfish) / flipped / ray T4-6")
		var x: float = 40.0
		for fam in [1, 2]:
			for tier in range(1, 7):
				_tile(Vector2(x, sy + 52.0), 64.0, Creature.make(fam, tier), {"phase": phase})
				_tile(Vector2(x, sy + 52.0 + 70.0), 64.0, Creature.make(fam, tier), {"phase": phase, "flip": true})
				x += 70.0
			x += 10.0
		for tier in range(4, 7):
			_tile(Vector2(x, sy + 52.0), 64.0, Creature.make(3, tier), {"phase": phase})
			_tile(Vector2(x, sy + 52.0 + 70.0), 64.0, Creature.make(3, tier), {"phase": phase + 2.0, "flip": true})
			x += 70.0

func _initialize() -> void:
	if OS.get_cmdline_user_args().has("bounds"):
		for code in [11, 12, 13, 14, 15, 16, 21, 22, 23, 24, 25, 26, 34, 35, 36]:
			var r: Rect2 = CreatureArt.body_bounds(code, 200.0)
			print("code %d  x %.2f..%.2f  y %.2f..%.2f" % [code, r.position.x, r.end.x, r.position.y, r.end.y])
		for code in [11, 12, 13, 14, 15, 16, 21, 22, 23, 24, 25, 26, 34, 35, 36]:
			var ops: Array = CreatureArt._ops_for(code, false, 0.8, 24)
			var cnt: Array = [0, 0, 0, 0]
			for op in ops:
				var n: int = 4 if (int(op[0]) == CreatureParts.OP_DYN and int(op[2]) == CreatureParts.DYN_SPARKLE) else 1
				for l in range(int(op[1]), 4):
					cnt[l] += n
			print("code %d draw calls (body) small=%d medium=%d full=%d" % [code, cnt[1], cnt[2], cnt[3]])
		quit()
		return
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
	img.save_png("res://dev/out/creature_sheet.png")
	print("creature sheet written")
	quit()
