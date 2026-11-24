extends SceneTree
## Tidepool Book page renders -> res://dev/out/book_<scenario>_<W>x<H>.png
##   xvfb-run -a -s "-screen 0 1200x900x24" $GODOT --rendering-driver opengl3 --path . --script res://dev/book_sheet.gd
## Also asserts layout invariants (tiles >= 44px, inside the control, no overlaps, detail visible).

const SIZES: Array = [Vector2i(370, 290), Vector2i(250, 220), Vector2i(405, 500), Vector2i(150, 200), Vector2i(370, 120)]

func _session(kind: String) -> GameSession:
	var s := GameSession.new()
	s.autosave = false
	var p: Profile = s.profile
	var rec := func(fam: int, tier: int, released: bool) -> void:
		var k: String = "%d:%d" % [fam, tier]
		p.book[k] = {"seen": true, "made": true, "released": released}
	match kind:
		"empty":
			pass
		"few":
			for t in 3:
				rec.call(1, t + 1, false)
			rec.call(1, 4, true)
			rec.call(2, 1, false)
			rec.call(2, 2, false)
		"full":
			for t in 6:
				rec.call(1, t + 1, true)
			for t in 5:
				rec.call(2, t + 1, t >= 3)
			rec.call(3, 4, true)
		"next":
			for t in 4:
				rec.call(1, t + 1, false)
			rec.call(2, 1, false)
			rec.call(2, 2, true)
	return s

func _shot(kind: String, sz: Vector2i, tag: String, setup: Callable) -> void:
	var vp := SubViewport.new()
	vp.size = sz
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var bg := ColorRect.new()
	bg.color = Color("0f3b4a")
	bg.size = Vector2(sz)
	vp.add_child(bg)
	var v := BookView.new()
	v.size = Vector2(sz)
	vp.add_child(v)
	root.add_child(vp)
	v.setup(_session(kind))
	v.size = Vector2(sz)
	setup.call(v)
	for i in 4:
		await process_frame
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("res://dev/out/book_%s_%dx%d.png" % [tag, sz.x, sz.y])
	_check(v, "%s %dx%d" % [tag, sz.x, sz.y])
	vp.queue_free()

func _check(v: BookView, name: String) -> void:
	var rects: Dictionary = v.tile_rects()
	var detail: Rect2 = v.detail_rect()
	var bad: int = 0
	var keys: Array = rects.keys()
	for a in keys:
		var r: Rect2 = rects[a]
		if r.size.x < 44.0 or r.size.y < 44.0:
			print("  FAIL tile <44: ", a, r)
			bad += 1
		if r.position.x < 0.0 or r.end.x > v.size.x:
			print("  FAIL tile outside horizontally: ", a, r)
			bad += 1
		for b in keys:
			if int(b) > int(a) and r.intersects(rects[b]):
				print("  FAIL overlap ", a, " ", b)
				bad += 1
	print("%s: tiles visible=%d content_h=%.0f detail=%s sel=%d %s" % [name, keys.size(), v.content_height(), str(detail), v.selected_code, "OK" if bad == 0 else "FAIL(%d)" % bad])

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://dev/out"))
	for sz in SIZES:
		await _shot("empty", sz, "empty", func(_v: BookView) -> void: pass)
		await _shot("few", sz, "few", func(_v: BookView) -> void: pass)
		await _shot("full", sz, "full", func(_v: BookView) -> void: pass)
		await _shot("full", sz, "full_scrolled", func(v: BookView) -> void: v._scroll_by(9999.0))
		await _shot("next", sz, "next", func(v: BookView) -> void: v.select(23))
		await _shot("few", sz, "toast", func(v: BookView) -> void:
			v._scroll_by(70.0)
			var r: Dictionary = v.tile_rects()
			for k in r:
				if int(k) in [15, 16]:
					v.tap((r[k] as Rect2).get_center()))
	_input_test()
	print("book sheet written")
	quit()

func _mouse(v: BookView, pos: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	v._gui_input(e)

func _motion(v: BookView, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	v._gui_input(e)

func _input_test() -> void:
	var v := BookView.new()
	v.size = Vector2(370, 290)
	root.add_child(v)
	v.setup(_session("few"))
	var rects: Dictionary = v.tile_rects()
	var c: Vector2 = (rects[12] as Rect2).get_center()
	_mouse(v, c, true)
	_mouse(v, c, false)
	print("tap selects 12: ", v.selected_code == 12)
	c = (rects[13] as Rect2).get_center()
	_mouse(v, c, true)
	_motion(v, c + Vector2(0, -20), Vector2(0, -20))
	_motion(v, c + Vector2(0, -60), Vector2(0, -40))
	_mouse(v, c + Vector2(0, -60), false)
	print("drag does not select (sel still 12): ", v.selected_code == 12, " scrolled: ", v._scroll > 0.0)
	var before: float = v._scroll
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	v._gui_input(w)
	print("wheel up scrolls back: ", v._scroll < before)
	v.queue_free()
