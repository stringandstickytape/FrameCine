extends RefCounted

## A small library in the layout of docs/library.md, for test_library and the picture: two shows, two films, and folders
## with no NFO. All made up; the art is generated. Videos are short test files named as the real ones would be.

const SHOWS := {
	"Harbour Lights (2011)": {"poster": [Color("#143a52"), Color("#d98f4e")], "fanart": [Color("#0f2433"), Color("#7a4a2c")]},
	"Night Ferry (2018)": {"poster": [Color("#2a1f3d"), Color("#c44e6b")], "fanart": [Color("#1b1428"), Color("#6b2a4a")]},
}


static func make(root: String) -> void:
	var show := "TV Shows/Harbour Lights (2011)"
	_text(root, show + "/tvshow.nfo", """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<tvshow>
	<title>Harbour Lights</title>
	<plot>A lighthouse keeper's daughter comes back to the town that blames her family for a wreck, and starts asking who moved the light.</plot>
	<premiered>2011-03-04</premiered>
	<genre>Drama</genre>
	<genre>Mystery</genre>
	<namedseason number="2">The Second Tide</namedseason>
</tvshow>
""")
	_art(root, show + "/poster.jpg", Vector2i(600, 900), SHOWS["Harbour Lights (2011)"]["poster"], "HARBOUR")
	_art(root, show + "/fanart.jpg", Vector2i(1280, 720), SHOWS["Harbour Lights (2011)"]["fanart"], "")
	var s1 := show + "/Season 01/Harbour Lights - "
	_episode(root, s1 + "S01E01 - The Long Tide", 1, 1, "The Long Tide",
			"Anna comes home for a funeral and finds the lamp room locked from the inside.", Color("#2b5a78"))
	_episode(root, s1 + "S01E02 - Salt", 1, 2, "Salt",
			"The harbourmaster's log has a page missing. Someone has been paying for silence for thirty years.",
			Color("#7a4a2c"))
	_video(root, s1 + "S01E03 - Fog Signal")  # No NFO, no thumbnail.
	_video(root, s1 + "S01E10 - Last Light")
	_text(root, s1 + "S01E10 - Last Light.nfo", "<episodedetails><title>Unfinished")  # A broken NFO.
	var s2 := show + "/Season 02/Harbour Lights - "
	_video(root, s2 + "S02E01-E02 - Double Bill")
	_text(root, s2 + "S02E01-E02 - Double Bill.nfo", """<episodedetails><title>Double Bill</title><season>2</season><episode>1</episode></episodedetails>
<episodedetails><title>Second Half</title><season>2</season><episode>2</episode></episodedetails>
""")
	_video(root, show + "/Specials/Harbour Lights - S00E01 - Behind the Lamp")

	var ferry := "TV Shows/Night Ferry (2018)"
	_text(root, ferry + "/tvshow.nfo", "<tvshow><title>Night Ferry</title><year>2018</year></tvshow>")
	_art(root, ferry + "/poster.jpg", Vector2i(600, 900), SHOWS["Night Ferry (2018)"]["poster"], "FERRY")
	_episode(root, ferry + "/Season 01/Night Ferry - S01E01 - Crossing", 1, 1, "Crossing",
			"Twelve passengers, eleven tickets.", Color("#6b2a4a"))

	var quiet := "Movies/Quiet Water (2019)"
	_video(root, quiet + "/Quiet Water (2019)")
	_text(root, quiet + "/Quiet Water (2019).nfo", """<movie>
	<title>Quiet Water</title>
	<plot>Two brothers rebuild their late father's boat over one summer, and find out what he kept in the hull.</plot>
	<tagline>Some things float back up.</tagline>
	<runtime>104</runtime>
	<premiered>2019-06-21</premiered>
	<genre>Drama</genre>
</movie>
""")
	_art(root, quiet + "/poster.jpg", Vector2i(600, 900), [Color("#1f4d44"), Color("#d6c27a")], "QUIET")
	_art(root, quiet + "/fanart.jpg", Vector2i(1280, 720), [Color("#12332d"), Color("#46705c")], "")
	var weekend := "Movies/The Long Weekend (1987)"
	_video(root, weekend + "/The Long Weekend (1987)")
	_text(root, weekend + "/movie.nfo", "<movie><title>The Long Weekend</title><year>1987</year></movie>")
	_video(root, "Movies/Holiday Clips/beach")
	_text(root, "Movies/Holiday Clips/notes.txt", "not a film")
	DirAccess.make_dir_recursive_absolute(root.path_join("Odds and Ends"))
	_video(root, "Loose Episode")


static func _episode(root: String, stem: String, season: int, episode: int, title: String, plot: String, tint: Color) -> void:
	_video(root, stem)
	_text(root, stem + ".nfo", "<episodedetails>\n<title>%s</title>\n<showtitle>Harbour Lights</showtitle>\n" % title
			+ "<season>%d</season>\n<episode>%d</episode>\n<plot>%s</plot>\n<runtime>44</runtime>\n" % [season, episode, plot]
			+ "<aired>2011-03-04</aired>\n</episodedetails>\n")
	_art(root, stem + "-thumb.jpg", Vector2i(640, 360), [tint, tint.darkened(0.6)], "")


static func _video(root: String, stem: String) -> void:
	_text(root, stem + ".mkv", "stand-in for a video")


static func _text(root: String, rel: String, text: String) -> void:
	var p := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## A diagonal wash with a low sun on it: enough to look like art and to show cropping. Drawn small and scaled up, as
## drawing pixels one by one in a script is slow.
static func _art(root: String, rel: String, size: Vector2i, colours: Array, _word: String) -> void:
	var small := Vector2i(size.x / 8, size.y / 8)
	var img := Image.create_empty(small.x, small.y, false, Image.FORMAT_RGB8)
	var a: Color = colours[0]
	var b: Color = colours[1]
	var sun := Vector2(small.x * 0.68, small.y * 0.3)
	var radius := small.y * 0.16
	for y in small.y:
		for x in small.x:
			var t := clampf((float(x) / small.x + float(y) / small.y) * 0.5, 0.0, 1.0)
			var c := a.lerp(b, t * t)
			var glow := clampf(1.0 - Vector2(x, y).distance_to(sun) / (radius * 3.0), 0.0, 1.0)
			c = c.lerp(b.lightened(0.5), glow * glow * 0.7)
			if y > small.y * 0.72 + small.y * 0.02 * sin(float(x) / small.x * 7.0):
				c = c.darkened(0.55)
			img.set_pixel(x, y, c)
	img.resize(size.x, size.y, Image.INTERPOLATE_CUBIC)
	var p := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	img.save_jpg(p, 0.9)
