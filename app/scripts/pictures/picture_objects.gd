extends RefCounted

## A kept picture (picture_library.gd) as an object to place (docs/features.md "Pictures"): a poster (a thin sheet),
## framed (the built-in picture frame), a canvas (a deep frame) or a cut-out (a standee, its picture's transparent
## pixels cut away, seen from both sides), each made at the picture's own shape (object_builtins.gd
## build_picture()) with the picture in its "Picture" part. Made once per picture and kind, as a user object of the
## library (tags picture and the kind; manifest picture_id and picture_as), the way a picture kept from a room's part
## is (room_keep.gd): so placing it, Move, physics (a wall one stays on its wall until pulled off), the film layer's
## cover and the kept room are all the object library's own.
##
##   object_for(picture_id, kind) -> {ok, id, new} or {ok: false, error}

const PictureLibrary := preload("res://scripts/pictures/picture_library.gd")
const ObjectLibrary := preload("res://scripts/assistant/object_library.gd")
const ObjectBuiltins := preload("res://scripts/assistant/object_builtins.gd")
const RoomModel := preload("res://scripts/assistant/room_model.gd")
const RoomKeep := preload("res://scripts/assistant/room_keep.gd")

const KINDS: Array[String] = ["poster", "framed", "canvas", "cutout"]
const MOUNTS := {"poster": "wall", "framed": "wall", "canvas": "wall", "cutout": "floor"}
## The material in the object's .glb that carries the picture.
const PICTURE_MATERIAL := "PictureImage"
## The words after the picture's title in the object's name (content, as the viewer's own objects' names are).
const NAME_WORDS := {"poster": "poster", "framed": "frame", "canvas": "canvas", "cutout": "cut-out"}


## The user object of this picture and kind: the one made before, else made now.
static func object_for(picture_id: String, kind: String) -> Dictionary:
	if not (kind in KINDS):
		return {"ok": false, "error": "as: one of %s" % ", ".join(KINDS)}
	var p := PictureLibrary.get_picture(picture_id)
	if p.is_empty():
		return {"ok": false, "error": "no picture %s (pictures lists them)" % picture_id}
	for m: Dictionary in PictureLibrary.objects_of(picture_id):
		if str(m.get("picture_as", "")) == kind:
			return {"ok": true, "id": m["id"], "new": false}
	var bytes := PictureLibrary.file_bytes(picture_id)
	if bytes.is_empty():
		return {"ok": false, "error": "the picture's file is missing"}
	var node := ObjectBuiltins.build_picture(kind, float(p.get("aspect", ObjectBuiltins.DEFAULT_ASPECT)))
	# The picture's part: unlit, so the room shows it as a picture (RoomModel.load_glb's pictures), white under it.
	var pic := RoomKeep._picture_material(Color.WHITE)
	# Not "Picture": the glTF writer makes names unique, and the part (its node and mesh) is called that.
	pic.resource_name = PICTURE_MATERIAL
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if str(mi.name) == "Picture" and mi.mesh != null:
			for s in mi.mesh.get_surface_count():
				mi.set_surface_override_material(s, pic)
	var glb := ObjectLibrary.to_glb(node)
	node.free()
	glb = RoomModel.with_picture(glb, PICTURE_MATERIAL, bytes)
	if glb.is_empty():
		return {"ok": false, "error": "the picture could not be put into the object"}
	var title := ObjectLibrary.clean_name(str(p.get("title", "")))
	var name := ("%s %s" % [title.left(30), NAME_WORDS[kind]]).strip_edges() if title != "" \
			else "Picture %s" % NAME_WORDS[kind]
	var r := ObjectLibrary.import_glb(glb, name, ["picture", kind], MOUNTS[kind],
			{"picture": true, "picture_id": picture_id, "picture_as": kind})
	if not bool(r.get("ok", false)):
		return {"ok": false, "error": str(r.get("error", "the object could not be made"))}
	return {"ok": true, "id": r["manifest"]["id"], "new": true}
