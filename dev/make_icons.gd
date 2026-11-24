extends SceneTree
## Renders the app icon from the game's own creature art.
##   xvfb-run godot --rendering-driver opengl3 --path . --script res://dev/make_icons.gd
## Writes assets/icon.png (512) and assets/icon_{192,180,144}.png. Full-bleed
## square artwork with the subject inside the central 80% (safe for maskable icons).

class IconArt extends Control:
	func _draw() -> void:
		var s: float = size.x
		draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s, 0), Vector2(s, s), Vector2(0, s)]),
			PackedColorArray([Color("1d7fa6"), Color("1d7fa6"), Color("0a3550"), Color("0a3550")]))
		# sand
		var sand := PackedVector2Array([Vector2(0, s)])
		for i in 9:
			sand.append(Vector2(s * i / 8.0, s * 0.80 + sin(i * 1.1) * s * 0.02))
		sand.append(Vector2(s, s))
		draw_colored_polygon(sand, Color("d9bd82"))
		for k in 3:
			draw_arc(Vector2(s * (0.22 + 0.1 * k), s * (0.25 - 0.05 * k)), s * 0.025, 0, TAU, 16, Color(1, 1, 1, 0.5), s * 0.008, true)
		CreatureArt.draw_creature(self, Creature.make(2, 4), Vector2(s * 0.40, s * 0.62), s * 0.46, {"badge": false})
		CreatureArt.draw_creature(self, Creature.make(1, 5), Vector2(s * 0.62, s * 0.38), s * 0.46, {"badge": false})

func _initialize() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 512)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var art := IconArt.new()
	art.size = Vector2(512, 512)
	vp.add_child(art)
	root.add_child(vp)
	for i in 6:
		await process_frame
	var img: Image = vp.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png("res://assets/icon.png")
	for n in [192, 180, 144]:
		var c: Image = img.duplicate()
		c.resize(n, n, Image.INTERPOLATE_LANCZOS)
		c.save_png("res://assets/icon_%d.png" % n)
	print("icons written")
	quit()
