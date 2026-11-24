extends SceneTree
## Renders a contact sheet of creature + decor art to res://dev/out/art_sheet.png
##   xvfb-run -a -s "-screen 0 900x900x24" $GODOT --rendering-driver opengl3 --path . --script res://dev/art_sheet.gd

const W := 1100
const H := 860

class Sheet extends Control:
	func _bg(r: Rect2, sand: bool) -> void:
		draw_polygon(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]),
			PackedColorArray([Pal.BG_TOP, Pal.BG_TOP, Pal.BG_BOTTOM, Pal.BG_BOTTOM]))
		if sand:
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * 0.30, r.size.x, r.size.y * 0.30), Pal.SAND_DARK)
			draw_rect(Rect2(r.position.x, r.end.y - r.size.y * 0.30, r.size.x, 3.0), Pal.SAND)

	func _label(p: Vector2, s: String) -> void:
		draw_string(ThemeDB.fallback_font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Pal.TEXT)

	func _draw() -> void:
		_bg(Rect2(0, 0, W, H), false)
		# creature rows: [family, tiers]; each band = 140px creature + two 56px ones (sand / water)
		var rows: Array = [[1, [1, 2, 3, 4, 5, 6]], [2, [1, 2, 3, 4, 5, 6]], [3, [4, 5, 6]]]
		var y: float = 0.0
		for ri in rows.size():
			var fam: int = rows[ri][0]
			var tiers: Array = rows[ri][1]
			draw_rect(Rect2(0, y + 150.0, W, 62), Pal.SAND_DARK)
			draw_rect(Rect2(0, y + 150.0, W, 3), Pal.SAND)
			for i in tiers.size():
				var tier: int = tiers[i]
				var cx: float = 80.0 + float(i) * 160.0
				CreatureArt.draw_creature(self, Creature.make(fam, tier), Vector2(cx, y + 76.0), 140.0, {"phase": 0.8})
				_label(Vector2(cx - 60, y + 12), "f%d t%d" % [fam, tier])
				CreatureArt.draw_creature(self, Creature.make(fam, tier), Vector2(cx - 36, y + 182.0), 56.0, {"phase": 0.8})
				CreatureArt.draw_creature(self, Creature.make(fam, tier), Vector2(cx + 36, y + 182.0), 56.0, {"phase": 0.8, "flip": true})
			y += 218.0
		# decor row: 150x195 and 56x73
		var dy: float = y + 4.0
		for kind in 5:
			var bx: float = 10.0 + float(kind) * 215.0
			var big := Rect2(bx, dy, 150, 195)
			_bg(big, kind % 2 == 1)
			DecorArt.draw(self, kind, big, 1.3, {})
			var small := Rect2(bx + 154, dy + 122, 56, 73)
			_bg(small, kind % 2 == 0)
			DecorArt.draw(self, kind, small, 1.3, {})
			var ghost := Rect2(bx + 154, dy + 40, 40, 52)
			_bg(ghost, false)
			DecorArt.draw(self, kind, ghost, 1.3, {"alpha": 0.5, "animate": false})

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
	img.save_png("res://dev/out/art_sheet.png")
	print("art sheet written")
	quit()
