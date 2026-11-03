extends SceneTree

## Turns a SOFA HRTF file (AES69, SimpleFreeFieldHRIR) into the compact pack the spatial audio bundles
## (app/audio/hrtf/*.fhrtf, docs/features.md #21): BinauralRenderer reads the SOFA file (libmysofa in the engine),
## resamples it to 48 kHz, equalises it to the diffuse field, takes the interaural delay out and puts it on its
## 48 x 14 grid of directions, 128 taps an ear. Needs an engine with BinauralRenderer (fork branch frame/binaural).
## Run from the repository root:
##   godot --headless --xr-mode off --path app --script res://tools/hrtf_pack.gd -- <in.sofa> <out.fhrtf> <name> <credit>

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4 or not ClassDB.class_exists("BinauralRenderer"):
		printerr("usage: -- <in.sofa> <out.fhrtf> <name> <credit> (an engine with BinauralRenderer)")
		quit(2)
		return
	var r: Object = ClassDB.instantiate("BinauralRenderer")
	var t := Time.get_ticks_msec()
	var err: int = r.load_hrtf(args[0])
	if err != OK:
		printerr("can't read %s: %s" % [args[0], r.get_last_error()])
		quit(1)
		return
	var info: Dictionary = r.get_hrtf_info()
	print("%s: %d directions measured (%s), read in %d ms" % [args[0].get_file(), info.get("measured", 0),
			info.get("name", ""), Time.get_ticks_msec() - t])
	err = r.save_hrtf(args[1], args[2], args[3])
	if err != OK:
		printerr("can't write %s (%d)" % [args[1], err])
		quit(1)
		return
	print("wrote %s (%d bytes)" % [args[1], FileAccess.get_file_as_bytes(args[1]).size()])
	quit(0)
