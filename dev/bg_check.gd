extends SceneTree
## Contrast report for the pool backdrop, board frame and tiles in all four tide phases.
##   xvfb-run -a -s "-screen 0 1200x1000x24" $GODOT --rendering-driver opengl3 --path . --script res://dev/bg_check.gd
## Exit code 1 if any check fails.

const GRID := Rect2(10, 184, 422, 488)
const HUD_H := 175
const MIN_TEXT := 4.5
const MIN_SURFACE := 1.4

class P extends Control:
	var phase: int = 1
	func _draw() -> void:
		var pal: Dictionary = BgArt.palette(phase)
		var rect := Rect2(0, 0, 540, 960)
		BgArt.draw_pool_backdrop_static(self, rect, GRID, pal)
		BgArt.draw_pool_backdrop_anim(self, rect, GRID, pal, 6.5, true)

func _lum_img(c: Color) -> float:
	return Tide.luminance(c)

func _initialize() -> void:
	var fails: int = 0
	for ph in 4:
		var vp := SubViewport.new()
		vp.size = Vector2i(540, 960)
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var p := P.new()
		p.phase = ph
		p.size = Vector2(540, 960)
		vp.add_child(p)
		root.add_child(vp)
		for i in 5:
			await process_frame
		var img: Image = vp.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		var pal: Dictionary = BgArt.palette(ph)
		# HUD band: the brightest pixel is the worst case for light text
		var hud_max: float = 0.0
		var hud_at: Vector2 = Vector2.ZERO
		var hud_sum: float = 0.0
		var n: int = 0
		for y in range(0, HUD_H, 2):
			for x in range(0, 540, 2):
				var l: float = Tide.luminance(img.get_pixel(x, y))
				if l > hud_max:
					hud_at = Vector2(x, y)
				hud_max = maxf(hud_max, l)
				hud_sum += l
				n += 1
		var text_worst: float = (Pal.TEXT.get_luminance() * 0.0) + Tide.contrast(Pal.TEXT, _gray(hud_max))
		var text_mean: float = Tide.contrast(Pal.TEXT, _gray(hud_sum / float(n)))
		# backdrop just outside the board frame (rim is 8px): sample a ring 12px out
		var ring: Rect2 = GRID.grow(13.0)
		var ring_max: float = 0.0
		var ring_at: Vector2 = Vector2.ZERO
		var ring_sum: float = 0.0
		var rn: int = 0
		var x: float = ring.position.x
		while x <= ring.end.x:
			for yy in [ring.position.y, ring.end.y]:
				var l2: float = Tide.luminance(img.get_pixel(int(clampf(x, 0, 539)), int(yy)))
				if l2 > ring_max:
					ring_at = Vector2(x, yy)
				ring_max = maxf(ring_max, l2)
				ring_sum += l2
				rn += 1
			x += 4.0
		var y2: float = ring.position.y
		while y2 <= ring.end.y:
			for xx in [ring.position.x, ring.end.x]:
				var l3: float = Tide.luminance(img.get_pixel(int(clampf(xx, 0, 539)), int(y2)))
				if l3 > ring_max:
					ring_at = Vector2(xx, y2)
				ring_max = maxf(ring_max, l3)
				ring_sum += l3
				rn += 1
			y2 += 4.0
		var tile_lo: float = minf(Tide.luminance(pal["tile_a"]), Tide.luminance(pal["tile_b"]))
		var tile_lo_c: Color = pal["tile_a"] if Tide.luminance(pal["tile_a"]) <= Tide.luminance(pal["tile_b"]) else pal["tile_b"]
		var tile_hi_c: Color = pal["tile_b"] if tile_lo_c == pal["tile_a"] else pal["tile_a"]
		var r_gap: float = minf(Tide.contrast(pal["tile_a"], pal["gap"]), Tide.contrast(pal["tile_b"], pal["gap"]))
		var r_frame: float = minf(Tide.contrast(pal["tile_a"], pal["board_frame"]), Tide.contrast(pal["tile_b"], pal["board_frame"]))
		var r_back: float = Tide.contrast(tile_lo_c, _gray(ring_max))
		var r_back_mean: float = Tide.contrast(tile_lo_c, _gray(ring_sum / float(rn)))
		var r_ab: float = Tide.contrast(tile_lo_c, tile_hi_c)
		var r_empty: float = Tide.contrast(pal["tile_empty"], pal["gap"])
		var r_ink: float = Tide.contrast(Pal.INK, Pal.SAND)
		var r_ink2: float = Tide.contrast(Pal.INK, pal["sand"])
		print("== %s ==" % Tide.phase_name(ph))
		print("  TEXT on HUD-band backdrop: worst %.2f at %s  mean %.2f   (>= %.1f) %s" % [text_worst, str(hud_at), text_mean, MIN_TEXT, _pf(text_worst >= MIN_TEXT)])
		print("  tile vs gap:               %.2f   (>= %.1f) %s   [empty vs gap %.2f, tile_a vs tile_b %.2f]" % [r_gap, MIN_SURFACE, _pf(r_gap >= MIN_SURFACE), r_empty, r_ab])
		print("  tile vs frame:             %.2f   (>= %.1f) %s" % [r_frame, MIN_SURFACE, _pf(r_frame >= MIN_SURFACE)])
		print("  tile vs backdrop (ring):   worst %.2f at %s  mean %.2f   (>= %.1f) %s" % [r_back, str(ring_at), r_back_mean, MIN_SURFACE, _pf(r_back >= MIN_SURFACE)])
		print("  INK on Pal.SAND:           %.2f   (>= %.1f) %s   [on phase sand %.2f]" % [r_ink, MIN_TEXT, _pf(r_ink >= MIN_TEXT), r_ink2])
		for ok in [text_worst >= MIN_TEXT, r_gap >= MIN_SURFACE, r_frame >= MIN_SURFACE, r_back >= MIN_SURFACE, r_ink >= MIN_TEXT]:
			if not ok:
				fails += 1
		if tile_lo < 0.0:
			fails += 1
		vp.queue_free()
	print("RESULT: %s (%d failing checks)" % ["PASS" if fails == 0 else "FAIL", fails])
	quit(1 if fails > 0 else 0)

func _pf(ok: bool) -> String:
	return "PASS" if ok else "FAIL"

## A grey whose relative luminance equals `lum` (for contrast against a luminance value).
func _gray(lum: float) -> Color:
	var v: float = lum * 12.92 if lum <= 0.0031308 else 1.055 * pow(lum, 1.0 / 2.4) - 0.055
	return Color(v, v, v)
