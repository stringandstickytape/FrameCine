extends RefCounted

## The assistants paired with this headset (docs/assistant.md): a name, when it paired, when it was last seen, and the
## SHA-256 of its token, in a file of their own (user://assistant_clients.cfg, owner read and write only), not in
## settings.cfg, so the dev link's `get` never sees it. The token itself is never kept, printed or returned again: an
## assistant that loses it pairs again.

const AssistantTls := preload("res://scripts/assistant/assistant_tls.gd")
const PATH := "user://assistant_clients.cfg"
const MAX_CLIENTS := 16

## Tests use another file.
var path := PATH
## [{id, name, token_sha256, paired_at, last_seen, address}]
var clients: Array[Dictionary] = []


func load_file() -> void:
	clients.clear()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	for id in cfg.get_sections():
		var h := str(cfg.get_value(id, "token_sha256", ""))
		if h.length() != 64:
			continue
		clients.append({"id": id, "name": str(cfg.get_value(id, "name", "")), "token_sha256": h,
				"paired_at": str(cfg.get_value(id, "paired_at", "")), "last_seen": str(cfg.get_value(id, "last_seen",
				"")), "address": str(cfg.get_value(id, "address", ""))})


func save() -> bool:
	var cfg := ConfigFile.new()
	for c in clients:
		for k in ["name", "token_sha256", "paired_at", "last_seen", "address"]:
			cfg.set_value(c["id"], k, c[k])
	var err := cfg.save(path)
	if err != OK:
		push_warning("Assistant: can't write the paired assistants (%s)" % error_string(err))
		return false
	AssistantTls.owner_only(path)
	return true


func is_empty() -> bool:
	return clients.is_empty()


## A new client: returns {client, token}. The token goes to the client once; only its hash is kept. The oldest is
## dropped beyond MAX_CLIENTS.
func add(client_name: String, address: String) -> Dictionary:
	var crypto := Crypto.new()
	var token := crypto.generate_random_bytes(32).hex_encode()
	var now := Time.get_datetime_string_from_system(false, true)
	var c := {"id": crypto.generate_random_bytes(6).hex_encode(), "name": client_name, "token_sha256":
			token.sha256_text(), "paired_at": now, "last_seen": now, "address": address}
	clients.append(c)
	while clients.size() > MAX_CLIENTS:
		clients.remove_at(0)
	save()
	return {"client": c, "token": token}


## The client holding this token, or {}.
func find(token: String) -> Dictionary:
	if token.length() != 64:
		return {}
	var h := token.sha256_text().to_ascii_buffer()
	var crypto := Crypto.new()
	var found := {}
	for c in clients:
		if crypto.constant_time_compare(h, str(c["token_sha256"]).to_ascii_buffer()):
			found = c
	return found


func by_id(id: String) -> Dictionary:
	for c in clients:
		if c["id"] == id:
			return c
	return {}


func forget(id: String) -> bool:
	for i in clients.size():
		if clients[i]["id"] == id:
			clients.remove_at(i)
			save()
			return true
	return false


func forget_all() -> void:
	clients.clear()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path) if path.begins_with("user://") else path)


## Without the hashes: for the panel and /status.
func public_list() -> Array:
	var out: Array = []
	for c in clients:
		out.append({"id": c["id"], "name": c["name"], "paired_at": c["paired_at"], "last_seen": c["last_seen"]})
	return out
