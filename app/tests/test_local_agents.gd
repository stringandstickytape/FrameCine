extends SceneTree

## The agents on the headset (scripts/agents/, ui/agent_pane.gd) with a stand-in for the window capture: the folders and
## files they get (the user's are kept), the player's MCP server in each agent's own config (no token, no tool allowed
## ahead), the hook script, finding a terminal by its class, the install card, voice typed
## in and spoken keys, the rule for when the stick and trigger are the agent's, the context, the voice target.
##
## godot --headless --xr-mode off --path app --script res://tests/test_local_agents.gd

const AgentTerminal := preload("res://scripts/agents/agent_terminal.gd")
const LocalAgents := preload("res://scripts/agents/local_agents.gd")
const WindowVideoSource := preload("res://scripts/video/window_video_source.gd")
const VideoScreen := preload("res://scripts/video_screen.gd")
const RoomSnapshot := preload("res://scripts/assistant/room_snapshot.gd")


class FakeX extends RefCounted:
	var windows: Array[Dictionary] = []
	var typed := ""
	var keys: Array[String] = []
	var captured := 0
	var updates := 0

	func open(_display := "") -> int:
		return OK

	func close() -> void:
		pass

	func list_windows(_all := false) -> Array[Dictionary]:
		return windows

	func capture(id: int) -> int:
		captured = id
		return OK

	func stop_capture() -> void:
		captured = 0

	func update() -> bool:
		updates += 1
		return false

	func get_texture() -> Texture2D:
		return ImageTexture.create_from_image(Image.create_empty(960, 960, false, Image.FORMAT_RGBA8))

	func get_size() -> Vector2i:
		return Vector2i(960, 960)

	func send_unicode(code: int, pressed: bool) -> void:
		if pressed:
			typed += String.chr(code)

	func send_godot_key(key: int, pressed: bool) -> void:
		if pressed:
			keys.append(OS.get_keycode_string(key))


## A hand for holding the window: the ray along its -Z, the laser calls ignored (as in test_pc_windows.gd).
class FakeHand extends Node3D:
	func get_ray_origin() -> Vector3:
		return global_position

	func get_ray_direction() -> Vector3:
		return -global_basis.z

	func set_laser(_on: bool, _length := 3.0, _hit := false, _beam := Color(), _dot := Color()) -> void:
		pass


class FakeGaze extends RefCounted:
	var calibrating := false
	var fitted := true
	var gone := false
	var origin := Vector3.ZERO
	var dir := Vector3.FORWARD

	func calibrated() -> bool:
		return fitted

	func ray() -> Array:
		return [] if gone else [origin, dir]


var _failures := 0
var _checks := 0
var main: Node3D
var fake_gaze: FakeGaze
var agents: LocalAgents
var fake: FakeX
var home := ""


func _init() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate() as Node3D
	main.settings.read_only = true
	root.add_child(main)
	current_scene = main
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	home = OS.get_user_data_dir().path_join("test_agents_home")
	_clear(home)
	DirAccess.make_dir_recursive_absolute(home)
	AgentTerminal.home_override = home
	AgentTerminal.terminal_override.assign(["/bin/true"])
	agents = main.local_agents
	agents.pair_on_start = false
	fake = FakeX.new()
	agents.x = fake
	_files_checks()
	_mcp_checks()
	await _hook_checks()
	await _start_checks()
	await _voice_checks()
	await _input_checks()
	await _context_checks()
	await _small_checks()
	_locale_checks()
	_detached_checks()
	_window_checks()
	_display_checks()
	agents.set_active("")
	agents.hide_pane()
	AgentTerminal.home_override = ""
	AgentTerminal.terminal_override.clear()
	agents.x = null
	_clear(home)
	print("test_local_agents: %d checks, %s" % [_checks, "all passed" if _failures == 0 else "%d FAILED" % _failures])
	quit(1 if _failures > 0 else 0)


func _files_checks() -> void:
	var folder := home.path_join("Claude")
	_check("prepare says nothing is wrong", AgentTerminal.prepare("claude") == "")
	var notes := FileAccess.get_file_as_string(folder.path_join("CLAUDE.md"))
	_check("CLAUDE.md written, with the guide's address", notes.contains("http://127.0.0.1:47801/")
			and notes.contains("speech to text"))
	var f := FileAccess.open(folder.path_join("CLAUDE.md"), FileAccess.WRITE)
	f.store_string(notes.replace(AgentTerminal.BLOCK_BEGIN, "My own line above.\n" + AgentTerminal.BLOCK_BEGIN)
			.replace("speech to text", "AN OLD TEXT OF THE APP") + "My own line below.\n")
	f.close()
	AgentTerminal.prepare("claude")
	var again_notes := FileAccess.get_file_as_string(folder.path_join("CLAUDE.md"))
	_check("the app's block is replaced, the user's lines stay", again_notes.contains("My own line above.\n")
			and again_notes.ends_with("My own line below.\n") and again_notes.contains("speech to text")
			and not again_notes.contains("AN OLD TEXT") and again_notes.count(AgentTerminal.BLOCK_BEGIN) == 1)
	_check("the library is described", again_notes.contains("Season 01/<Show> - S01E01 - <Title>.<ext>")
			and again_notes.contains("Movies/<Title> (<Year>)/<Title> (<Year>).<ext>")
			and again_notes.contains("tvshow.nfo"))
	_check("the words are defined, so it needn't ask", again_notes.contains("\"Import\" or \"add to the library\"")
			and again_notes.contains("\"Info files\" means"))
	_check("shares go through the player", again_notes.contains("Never mount a share")
			and again_notes.contains("~/.smb-password") and again_notes.contains("cmd=copy_to_library")
			and again_notes.contains("cmd=list_dir") and again_notes.contains("path=network://")
			and again_notes.contains("https://127.0.0.1:47802/command"))
	_check("no placeholder is left", not again_notes.contains("<<"))
	_check("it stays short: it loads in every session (%d lines)" % again_notes.count("\n"),
			again_notes.count("\n") < 50)
	AgentTerminal.prepare("claude")
	_check("starting again changes nothing", FileAccess.get_file_as_string(folder.path_join("CLAUDE.md")) == again_notes)
	var old := AgentTerminal.instructions_text("claude").get_slice("## The Library", 0).strip_edges() + "\n" \
			+ AgentTerminal.OLD_LINES[0] + "\nAdded by hand.\n"
	var merged := AgentTerminal.merged_instructions(old, "claude")
	_check("a file from before the block: the app's lines go, the user's stay", merged.begins_with(AgentTerminal.BLOCK_BEGIN)
			and merged.ends_with("\nAdded by hand.\n") and merged.count("# You are running inside") == 1
			and merged.count("columns and") == 1)
	var theirs := AgentTerminal.merged_instructions("All mine.\n", "claude")
	_check("a file of the user's own keeps every line", theirs.contains("All mine.") and theirs.contains(AgentTerminal.BLOCK_END))
	var settings_path := folder.path_join(".claude/settings.json")
	var s: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	_check("hooks: the prompt hook prints the context", str(s["hooks"]["UserPromptSubmit"][0]["hooks"][0]["command"])
			.ends_with("hook.sh' prompt"))
	_check("hooks: a permission prompt is seen at once", str(s["hooks"]["PermissionRequest"]).contains("waiting")
			and str(s["hooks"]["PreToolUse"]).contains("AskUserQuestion"))
	s["permissions"] = {"allow": ["Bash(ls:*)"]}
	(s["hooks"]["Stop"] as Array).append({"hooks": [{"type": "command", "command": "my-own-stop-hook"}]})
	f = FileAccess.open(settings_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(s))
	f.close()
	AgentTerminal.prepare("claude")
	var again: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	_check("the user's settings stay, ours aren't doubled", again["permissions"]["allow"] == ["Bash(ls:*)"]
			and (again["hooks"]["Stop"] as Array).size() == 2 and (again["hooks"]["UserPromptSubmit"] as Array).size() == 1
			and str(again["hooks"]["Stop"]).contains("my-own-stop-hook"))
	f = FileAccess.open(settings_path, FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	AgentTerminal.prepare("claude")
	_check("a settings file we can't read is left alone", FileAccess.get_file_as_string(settings_path) == "{ not json")
	DirAccess.remove_absolute(settings_path)
	AgentTerminal.prepare("codex")
	_check("Codex: AGENTS.md and .codex/hooks.json in ~/Codex", FileAccess.file_exists(home.path_join("Codex/AGENTS.md"))
			and FileAccess.get_file_as_string(home.path_join("Codex/.codex/hooks.json")).contains("UserPromptSubmit"))
	var run := FileAccess.get_file_as_string(home.path_join("Codex/.player/run.sh"))
	_check("Codex: signs in by device code when it isn't signed in", run.contains("login --device-auth"))
	for id: String in AgentTerminal.AGENTS:
		var r := FileAccess.get_file_as_string(AgentTerminal.player_dir(id).path_join("run.sh"))
		_check("%s: its own approval prompts stay on, a full path" % id, not r.contains("dangerously")
				and not r.contains("--yolo") and not r.contains("bypass") and r.contains(home))
	var briefed := AgentTerminal.run_text("claude")
	_check("a new session: the briefing as an initial prompt, not -p", briefed.contains("\"$BIN\" \"$P\"")
			and briefed.contains(AgentTerminal.GUIDE_URL) and not briefed.contains(" -p "))
	_check("a restart continues, afresh if there is nothing to continue", briefed.contains(
			"\"$BIN\" --continue || \"$BIN\" \"$P\"") and AgentTerminal.run_text("codex").contains(
			"\"$BIN\" resume --last || \"$BIN\" \"$P\""))
	var claude_run := AgentTerminal.run_text("claude")
	_check("the terminal starts with the tools' paths", claude_run.contains("$HOME/.local/bin:$PATH")
			and claude_run.contains("export PERL5LIB=\"$HOME/perl5/lib/perl5"))
	var codex_notes := AgentTerminal.instructions_text("codex")
	_check("the instructions say how to get a video here", codex_notes.contains("~/Videos/From assistant")
			and codex_notes.contains("skip the guide's fetch step") and codex_notes.contains("%(title)s.%(ext)s")
			and codex_notes.contains("not AV1") and codex_notes.contains("get_iplayer"))
	var fresh := AgentTerminal.run_text("claude", false, false, true)
	_check("fresh: the briefing, and nothing continued", fresh.contains("\"$BIN\" \"$P\"")
			and not fresh.contains("--continue"))
	var plain := AgentTerminal.run_text("claude", false, true)
	_check("plain: it just starts and waits", not plain.contains("P='") and plain.contains("  \"$BIN\"\n"))
	_check("no token on any command line", not briefed.contains("Bearer"))
	AgentTerminal.write_link("claude", "ab".repeat(32), "sha256//PIN")
	_check("the link file: a curl config, read back", AgentTerminal.link_token("claude") == "ab".repeat(32)
			and FileAccess.get_file_as_string(AgentTerminal.link_path("claude")).contains("pinnedpubkey = \"sha256//PIN\""))
	_check("the link file is the user's alone (%d)" % FileAccess.get_unix_permissions(AgentTerminal.link_path("claude")),
			FileAccess.get_unix_permissions(AgentTerminal.link_path("claude")) & 63 == 0)
	AgentTerminal.forget_link("Claude Code on this headset")
	_check("forgetting the client deletes it", not FileAccess.file_exists(AgentTerminal.link_path("claude")))
	var install := AgentTerminal.run_text("codex", true)
	_check("Codex's install: the release for this machine", install.contains(
			"releases/latest/download/codex-$a-unknown-linux-musl.tar.gz") and install.contains("uname -m"))
	_check("Claude Code's install: the official installer", AgentTerminal.run_text("claude", true).contains(
			"curl -fsSL https://claude.ai/install.sh | bash"))
	var args := AgentTerminal.terminal_args("claude", "/usr/bin/xterm")
	_check("xterm: a class to find it by, takes the capture's keys, keeps the title (%s)" % [args], args.has("frame-claude")
			and args.has("*allowSendEvents: true") and args.has("*allowTitleOps: false")
			and args.has("%dx%d+0+0" % [AgentTerminal.COLUMNS, AgentTerminal.LINES]))
	_check("the other terminals have their lines", AgentTerminal.terminal_args("claude", "/usr/bin/konsole").has(
			"--separate") and AgentTerminal.terminal_args("claude", "/usr/bin/lxterminal").has("--no-remote"))


## The player's MCP server in each agent's own config: the adapter copied, the config pointing at it with the link file,
## the user's entries kept, no token anywhere but the link file, and no tool allowed ahead.
func _mcp_checks() -> void:
	var token := "cd".repeat(32)
	AgentTerminal.write_link("claude", token, "sha256//PIN")
	AgentTerminal.prepare("claude")
	var folder := home.path_join("Claude")
	var mcp_path := folder.path_join(".mcp.json")
	var text := FileAccess.get_file_as_string(mcp_path)
	var cfg: Variant = JSON.parse_string(text)
	var server: Dictionary = cfg["mcpServers"][AgentTerminal.MCP_NAME] if cfg is Dictionary else {}
	var args: Array = server.get("args", [])
	_check("Claude Code: .mcp.json has the player's server on stdio (%s)" % [server], server.get("type") == "stdio"
			and str(server.get("command", "")).ends_with("python3")
			and str(args[0]) == AgentTerminal.player_dir("claude").path_join("mcp/mcp_server.py")
			and args.slice(1) == ["--url", AgentTerminal.API_URL, "--config", AgentTerminal.link_path("claude")])
	_check("no token in .mcp.json or on its command line", not text.contains(token) and not text.contains("Bearer")
			and not " ".join(AgentTerminal.mcp_command("claude")).contains(token))
	var copied := true
	for f: String in AgentTerminal.MCP_FILES:
		var to := AgentTerminal.player_dir("claude").path_join("mcp").path_join(f)
		copied = copied and FileAccess.get_file_as_string(to) == FileAccess.get_file_as_string("res://assistant/tools/" + f) \
				and FileAccess.get_file_as_string(to) != ""
	_check("the adapter and its helper are copied beside the hook", copied)
	_check("the player's folder is the user's alone (%o)" % FileAccess.get_unix_permissions(AgentTerminal.player_dir("claude")),
			FileAccess.get_unix_permissions(AgentTerminal.player_dir("claude")) & 63 == 0)
	var python := str(server.get("command", ""))
	if FileAccess.file_exists(python):
		var out := []
		var code := OS.execute(python, [str(args[0]), "--help"], out, true)
		_check("the copied adapter runs (%d)" % code, code == 0 and str(out).contains("--config"))
	var settings_path := folder.path_join(".claude/settings.json")
	var settings_text := FileAccess.get_file_as_string(settings_path)
	var s: Dictionary = JSON.parse_string(settings_text)
	_check("the server is enabled by name, nothing else (%s)" % [s.get("enabledMcpjsonServers")],
			s.get("enabledMcpjsonServers") == [AgentTerminal.MCP_NAME] and not s.has("enableAllProjectMcpServers"))
	_check("no tool is allowed ahead", not settings_text.contains("mcp__") and not s.has("permissions"))
	# The user's own servers and choices stay.
	var mine := {"mcpServers": {"notes": {"command": "notes-server", "args": ["--quiet"]}}, "theirs": 1}
	_put(mcp_path, JSON.stringify(mine))
	s["enabledMcpjsonServers"] = ["notes"]
	s["disabledMcpjsonServers"] = ["other"]
	_put(settings_path, JSON.stringify(s))
	AgentTerminal.prepare("claude")
	var merged: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(mcp_path))
	_check("the user's servers in .mcp.json stay", merged["mcpServers"]["notes"] == mine["mcpServers"]["notes"]
			and merged.get("theirs") == 1.0 and merged["mcpServers"].has(AgentTerminal.MCP_NAME))
	s = JSON.parse_string(FileAccess.get_file_as_string(settings_path))
	_check("the user's enabled and disabled servers stay (%s)" % [s.get("enabledMcpjsonServers")],
			s["enabledMcpjsonServers"] == ["notes", AgentTerminal.MCP_NAME] and s["disabledMcpjsonServers"] == ["other"])
	var before := FileAccess.get_file_as_string(mcp_path)
	AgentTerminal.prepare("claude")
	_check("starting again changes nothing", FileAccess.get_file_as_string(mcp_path) == before)
	_put(mcp_path, "{ not json")
	AgentTerminal.prepare("claude")
	_check("an .mcp.json we can't read is left alone", FileAccess.get_file_as_string(mcp_path) == "{ not json")
	DirAccess.remove_absolute(mcp_path)
	# Codex: a marked block at the end of .codex/config.toml.
	AgentTerminal.write_link("codex", token, "sha256//PIN")
	AgentTerminal.prepare("codex")
	var toml_path := home.path_join("Codex/.codex/config.toml")
	var toml := FileAccess.get_file_as_string(toml_path)
	_check("Codex: its config.toml declares the server in the app's block (%s)" % toml.c_escape(),
			toml.begins_with(AgentTerminal.TOML_BEGIN) and toml.ends_with(AgentTerminal.TOML_END + "\n")
			and toml.contains("[mcp_servers.%s]\n" % AgentTerminal.MCP_NAME)
			and toml.contains("args = [\"%s\",\"--url\",\"%s\",\"--config\",\"%s\"]" % [
			AgentTerminal.player_dir("codex").path_join("mcp/mcp_server.py"), AgentTerminal.API_URL,
			AgentTerminal.link_path("codex")]) and toml.contains("tool_timeout_sec = 300"))
	_check("Codex: no token in its config, no approval set ahead", not toml.contains(token)
			and not toml.contains("approval"))
	_put(toml_path, "model = \"m\"\n\n[profiles.quiet]\nverbosity = \"low\"\n" + toml + "late = 2\n")
	AgentTerminal.prepare("codex")
	var kept := FileAccess.get_file_as_string(toml_path)
	_check("Codex: the user's lines stay, above the block, which stays last (%s)" % kept.c_escape(),
			kept.begins_with("model = \"m\"\n\n[profiles.quiet]\nverbosity = \"low\"\nlate = 2\n\n"
			+ AgentTerminal.TOML_BEGIN) and kept.count(AgentTerminal.TOML_BEGIN) == 1
			and kept.ends_with(AgentTerminal.TOML_END + "\n"))
	AgentTerminal.prepare("codex")
	_check("Codex: starting again changes nothing", FileAccess.get_file_as_string(toml_path) == kept)
	var own := "[mcp_servers.%s]\ncommand = \"my-own\"\n" % AgentTerminal.MCP_NAME
	_check("Codex: a server of the user's own under our name wins",
			AgentTerminal.merged_codex_config(own + "\n" + AgentTerminal.codex_block("codex"), "codex") == own + "\n")
	_check("both briefings name the tools and keep curl as the fallback", AgentTerminal.BRIEFING.contains(
			AgentTerminal.MCP_NAME) and AgentTerminal.BRIEFING.contains("curl -K") and not AgentTerminal.BRIEFING.contains("'")
			and AgentTerminal.instructions_text("codex").contains(".codex/config.toml")
			and AgentTerminal.instructions_text("claude").contains("skip `wait_for_viewer_message`"))
	AgentTerminal.forget_link("Claude Code on this headset")
	AgentTerminal.forget_link("Codex on this headset")


func _put(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _hook_checks() -> void:
	AgentTerminal.prepare("claude")
	var dir := AgentTerminal.player_dir("claude")
	var f := FileAccess.open(dir.path_join("context.txt"), FileAccess.WRITE)
	f.store_string("[On the headset: a film.]\n")
	f.close()
	var hook := dir.path_join("hook.sh")
	var out: Array = []
	var t0 := Time.get_ticks_usec()
	var code := OS.execute("sh", ["-c", "echo '{}' | sh '%s' prompt" % hook], out)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	_check("the prompt hook prints the context (%s; %.1f ms)" % [str(out).strip_edges(), ms], code == 0
			and str(out[0]).contains("a film") and FileAccess.file_exists(dir.path_join("hook_seen")))
	OS.execute("sh", ["-c", "echo '{}' | sh '%s' waiting" % hook], out)
	_check("waiting marks a prompt", FileAccess.file_exists(dir.path_join("waiting")))
	OS.execute("sh", ["-c", "echo '{}' | sh '%s' clear" % hook], out)
	_check("clear takes it off", not FileAccess.file_exists(dir.path_join("waiting")))
	await process_frame


func _start_checks() -> void:
	# Not installed: a card asks; nothing starts without Install.
	var card: Node = main.ui.get("card")
	agents.open_agent("claude")
	await _frames(2)
	_check("not installed: a card asks (%s)" % card.get("_text").text, card.is_showing()
			and str(card.get("_text").text).contains("isn't installed") and agents.active == "")
	card.dismiss("no")
	await _frames(2)
	_check("No: nothing starts", agents.active == "")
	agents.open_agent("claude")
	await _frames(2)
	card.dismiss("install")
	await _frames(2)
	_check("Install: the terminal runs the installer", agents.active == "claude" and FileAccess.get_file_as_string(
			home.path_join("Claude/.player/run.sh")).contains("install.sh") and agents.pane_shown())
	# Installed now; its terminal shows up by its class.
	DirAccess.make_dir_recursive_absolute(home.path_join(".local/bin"))
	for bin in ["claude", "codex"]:
		var f := FileAccess.open(home.path_join(".local/bin").path_join(bin), FileAccess.WRITE)
		f.store_string("#!/bin/sh\n")
		f.close()
	fake.windows = [{"id": 0x400001, "class": "frame-claude", "instance": "xterm", "title": "whatever"}]
	await _seconds(0.7)
	_check("found by its class, running, captured for the pane (%x)" % fake.captured, agents.is_running("claude")
			and fake.captured == 0x400001)
	var ups := fake.updates
	await _frames(3)
	_check("the capture updates while the pane shows", fake.updates > ups)
	_check("opening it sets the voice", str(main.settings.get_value("assistant", "voice_to", "")) == "claude"
			and main.ui.voice_target() == agents.push_to_talk())
	# Leaving it and coming back: the same window, no second terminal.
	agents.hide_pane()
	await _seconds(0.3)
	ups = fake.updates
	await _frames(3)
	_check("hidden: no capture, the terminal still runs", fake.captured == 0 and fake.updates == ups
			and agents.is_running("claude"))
	AgentTerminal.terminal_override.assign(["/nonexistent/would-fail"])
	agents.open_agent("claude")
	await _frames(2)
	_check("opening it again finds the same window, nothing starts", fake.captured == 0x400001 and agents.pane_shown())
	AgentTerminal.terminal_override.assign(["/bin/true"])
	# The terminal closed with a prompt up: the marks must not outlive that session.
	var kept: Array = fake.windows
	fake.windows = []
	await _seconds(0.7)
	var marks := AgentTerminal.player_dir("claude")
	for mark in ["started", "waiting", "hook_seen"]:
		FileAccess.open(marks.path_join(mark), FileAccess.WRITE).close()
	agents.open_agent("claude")
	await _frames(2)
	_check("a new terminal: the last session's marks go", not FileAccess.file_exists(marks.path_join("waiting"))
			and not FileAccess.file_exists(marks.path_join("hook_seen")))
	DirAccess.remove_absolute(marks.path_join("started"))
	fake.windows = kept
	await _seconds(0.7)
	# Two agents, one active.
	fake.windows.append({"id": 0x500001, "class": "frame-codex", "instance": "xterm", "title": ""})
	await _seconds(0.7)
	_check("both run (%s)" % [agents.running()], agents.running().size() == 2)
	var row: Node = main.ui.ui.system.assistant_row
	_check("the voice switch lists the ones running (%s)" % [row.voice_targets()], row.voice_targets().has("claude")
			and row.voice_targets().has("codex") and str(row.voice_targets()["codex"]) == "Codex on this headset")
	agents.open_agent("codex")
	await _frames(2)
	_check("one is active: the pane and the voice go to it", agents.active == "codex" and fake.captured == 0x500001
			and str(main.settings.get_value("assistant", "voice_to", "")) == "codex")
	agents.open_agent("claude")
	await _frames(2)


func _voice_checks() -> void:
	var hook_seen := AgentTerminal.player_dir("claude").path_join("hook_seen")
	FileAccess.open(hook_seen, FileAccess.WRITE).close()
	fake.typed = ""
	fake.keys.clear()
	agents.deliver("  make the sky darker ")
	_check("the words go straight in (%s)" % fake.typed, fake.typed == "make the sky darker" and fake.keys.is_empty())
	await _seconds(LocalAgents.ENTER_DELAY + 0.1)
	_check("then Enter, a moment later", fake.keys == ["Enter"])
	fake.typed = ""
	fake.keys.clear()
	agents.deliver("Two.")
	await _seconds(0.3)
	_check("\"two\" alone is the key (%s, %s)" % [fake.typed, fake.keys], fake.typed == "2" and fake.keys.is_empty())
	fake.keys.clear()
	fake.typed = ""
	agents.deliver("Escape")
	await _seconds(0.05)
	_check("\"escape\" too", fake.keys == ["Escape"] and fake.typed == "")
	DirAccess.remove_absolute(hook_seen)
	fake.keys.clear()
	fake.typed = ""
	agents.deliver("hello there")
	await _seconds(0.3)
	_check("before the session's first hook: Escape first, so Enter can't say yes at a prompt nobody announced (%s)"
			% str(fake.keys), fake.keys == ["Escape", "Enter"] and fake.typed == "hello there")
	FileAccess.open(hook_seen, FileAccess.WRITE).close()
	fake.keys.clear()
	fake.typed = ""
	agents.deliver("yes")
	await _seconds(0.3)
	_check("\"yes\" with no prompt waiting is a word (%s)" % fake.typed, fake.typed == "yes" and fake.keys == ["Enter"])
	fake.keys.clear()
	fake.typed = ""
	agents.deliver("No.")
	await _seconds(0.3)
	_check("a lone \"no\" with no prompt known: Escape, then the word (%s, %s)" % [fake.typed, fake.keys],
			fake.typed == "No." and fake.keys == ["Escape", "Enter"])
	var w := FileAccess.open(AgentTerminal.player_dir("claude").path_join("waiting"), FileAccess.WRITE)
	w.close()
	await _seconds(0.7)
	_check("the hook's mark: waiting", agents.waiting())
	fake.typed = ""
	fake.keys.clear()
	agents.deliver("what does that do")
	await _seconds(0.3)
	_check("words at a prompt are not typed: Enter would choose for the viewer (%s, %s)" % [fake.typed, fake.keys],
			fake.typed == "" and fake.keys.is_empty() and agents.waiting())
	_set_mark_now("claude")
	agents.deliver("still a question")
	await _seconds(0.3)
	_check("a prompt that came since the last look counts too", fake.typed == "" and fake.keys.is_empty())
	fake.typed = ""
	fake.keys.clear()
	agents.deliver("Yes.")
	await _seconds(0.05)
	_check("\"yes\" at a prompt is its first choice, and the mark goes (%s)" % fake.typed, fake.typed == "1"
			and not agents.waiting() and not FileAccess.file_exists(AgentTerminal.player_dir("claude").path_join("waiting")))
	w = FileAccess.open(AgentTerminal.player_dir("claude").path_join("waiting"), FileAccess.WRITE)
	w.close()
	await _seconds(0.7)
	fake.keys.clear()
	agents.deliver("no")
	await _seconds(0.05)
	_check("\"no\" at a prompt is Escape for Claude Code", fake.keys == ["Escape"])
	# Codex: its keys, and the context line ahead of the words until its hook has run.
	agents.open_agent("codex")
	await _frames(2)
	main.current_path = "stub://flat_sbs"
	DirAccess.remove_absolute(AgentTerminal.player_dir("codex").path_join("hook_seen"))
	fake.typed = ""
	fake.keys.clear()
	agents.deliver("what is this film")
	await _seconds(0.45)
	_check("Codex before its hook runs: a bracketed line first (%s)" % fake.typed, fake.typed.begins_with("[")
			and fake.typed.ends_with("] what is this film"))
	_check("and Escape ahead of it (%s)" % str(fake.keys), fake.keys == ["Escape", "Enter"])
	var seen := FileAccess.open(AgentTerminal.player_dir("codex").path_join("hook_seen"), FileAccess.WRITE)
	seen.close()
	fake.typed = ""
	agents.deliver("what is this film")
	await _seconds(0.3)
	_check("after that, the words alone", fake.typed == "what is this film")
	main.current_path = ""
	var y := FileAccess.open(AgentTerminal.player_dir("codex").path_join("waiting"), FileAccess.WRITE)
	y.close()
	await _seconds(0.7)
	fake.typed = ""
	agents.deliver("yes")
	await _seconds(0.05)
	_check("Codex's yes is y (%s)" % fake.typed, fake.typed == "y")
	agents.open_agent("claude")
	await _frames(2)
	_check("no shell: a word is only ever typed as words", not fake.keys.has("Ctrl"))


## A look from a metre in front of the pane, at x and y metres from its middle in its own plane.
## The pane eases in and out, and a press in the middle turns it back from where it is, with no jump in what shows.
func _pane_fade_checks() -> void:
	var pane: Node3D = agents.get_node("AgentPane")
	var quad: MeshInstance3D = pane.get_node("AgentQuad")
	agents.hide_pane()
	await _seconds(0.3)
	_check("gone from sight when hidden", not pane.visible)
	agents.toggle_pane()
	await _seconds(pane.FADE_SECONDS * 0.5)
	var mat: ShaderMaterial = quad.material_override
	var part: float = mat.get_shader_parameter("opacity")
	_check("half way in (%.2f), and smaller" % part, part > 0.05 and part < 0.95 and quad.scale.x < 1.0)
	var foot := quad.position.y - (quad.mesh as QuadMesh).size.y * 0.5 * quad.scale.y
	_check("it grows out of its bottom edge", absf(foot + (quad.mesh as QuadMesh).size.y * 0.5) < 1e-5)
	var half: float = (quad.mesh as QuadMesh).size.x * 0.5
	_look_at_pane(pane, half * (quad.scale.x + 1.0) * 0.5, 0)
	_check("the hit test follows its real size", not pane.looked_at(fake_gaze.origin, fake_gaze.dir, 0.0))
	_look_at_pane(pane, half * quad.scale.x * 0.98, 0)
	_check("and takes all of it", pane.looked_at(fake_gaze.origin, fake_gaze.dir, 0.0))
	var worst := 0.0
	var last := part
	agents.toggle_pane()
	for i in 12:
		await process_frame
		var now: float = mat.get_shader_parameter("opacity")
		worst = maxf(worst, absf(now - last))
		last = now
		if i % 4 == 3:
			agents.toggle_pane()
	_check("rapid presses move it in small steps (%.2f at most)" % worst, worst < 0.25 and pane.visible)
	agents.hide_pane()
	var captured := fake.captured
	await _frames(1)
	_check("the capture lasts through the fade", captured != 0 and fake.captured == captured)
	await _seconds(0.3)
	_check("and ends with it", fake.captured == 0)


## Y: on the pointer hand only, not under a calibration, with the menu open too; shows and hides the pane with the agent
## left working;
## with none running, starts the last one used, or the first installed, or asks.
func _y_checks(hand: Node) -> void:
	var voice := str(main.settings.get_value("assistant", "voice_to", ""))
	_check("the right hand is the one with the talk", hand == main.right_hand)
	agents.on_agent_button(hand)
	_check("Y shows the pane", agents.pane_shown())
	agents.on_agent_button(hand)
	_check("Y hides it", not agents.pane_shown())
	_check("the agent keeps working", agents.is_running("claude") and agents.active == "claude")
	_check("the voice stays", str(main.settings.get_value("assistant", "voice_to", "")) == voice)
	main.ui.set_pointer_hand(main.left_hand)
	agents.on_agent_button(main.right_hand)
	_check("the left hand points: Y does nothing", not agents.pane_shown())
	main.ui.set_pointer_hand(main.right_hand)
	main.set_menu_shown(true)
	agents.on_agent_button(hand)
	_check("the menu open: Y still shows the pane", agents.pane_shown())
	_check("but the menu keeps the stick and trigger", not agents.has_input(hand))
	agents.on_agent_button(hand)
	_check("and Y hides it again", not agents.pane_shown())
	main.set_menu_shown(false)
	var gaze: Object = agents.gaze_override
	agents.gaze_override = fake_gaze
	fake_gaze.calibrating = true
	agents.on_agent_button(hand)
	_check("a calibration has it: Y does nothing", not agents.pane_shown())
	fake_gaze.calibrating = false
	agents.gaze_override = gaze
	_check("nothing running, last used first", agents._agent_to_open() == "claude")
	var kept: Array = fake.windows
	var running := agents._running.duplicate()
	agents.set_active("")
	fake.windows = []
	agents._running.clear()
	main.settings.set_value("assistant", "last_agent", "nobody")
	_check("no last agent: the first installed", agents._agent_to_open() == AgentTerminal.AGENTS.keys()[0])
	var bin := home.path_join(".local/bin")
	for name in ["claude", "codex"]:
		DirAccess.remove_absolute(bin.path_join(name))
	var card: Node = main.ui.get("card")
	agents.on_agent_button(hand)
	await _frames(2)
	_check("none installed: the card asks", card.is_showing() and str(card.get("_text").text).contains("isn't installed")
			and agents.active == "")
	card.dismiss("no")
	await _frames(2)
	for name in ["claude", "codex"]:
		var f := FileAccess.open(bin.path_join(name), FileAccess.WRITE)
		f.store_string("#!/bin/sh\n")
		f.close()
	fake.windows = kept
	agents._running.assign(running)
	agents.set_active("claude")
	await _seconds(0.7)


func _look_at_pane(pane: Node3D, x_m: float, y_m: float) -> void:
	fake_gaze.origin = pane.global_transform * Vector3(0, 0, 1)
	fake_gaze.dir = (pane.global_transform * Vector3(x_m, y_m, 0) - fake_gaze.origin).normalized()


func _gaze_checks(hand: Node) -> void:
	fake_gaze = FakeGaze.new()
	agents.gaze_override = fake_gaze
	agents.open_agent("claude")
	await _frames(2)
	if not agents.pane_shown():
		agents.toggle_pane()
	await _seconds(0.3)
	var pane: Node3D = agents.get_node("AgentPane")
	var half: Vector2 = (pane.get_node("AgentQuad").mesh as QuadMesh).size * 0.5
	var margin := tan(deg_to_rad(agents.GAZE_MARGIN_DEG))
	_look_at_pane(pane, 0, 0)
	_check("a look at the middle meets the pane", pane.looked_at(fake_gaze.origin, fake_gaze.dir, 3.0))
	_look_at_pane(pane, half.x + margin * 0.9, 0)
	_check("just past the edge, within the margin", pane.looked_at(fake_gaze.origin, fake_gaze.dir, 3.0))
	_look_at_pane(pane, half.x + margin * 1.2, 0)
	_check("past the margin, no", not pane.looked_at(fake_gaze.origin, fake_gaze.dir, 3.0))
	_check("from behind, no", not pane.looked_at(pane.global_transform * Vector3(0, 0, -1), pane.global_basis.z, 3.0))
	_check("away from it, no", not pane.looked_at(pane.global_transform * Vector3(0, 0, 1), pane.global_basis.z, 3.0))

	_look_at_pane(pane, 0, 0)
	await _seconds(agents.GAZE_ON * 0.3)
	_check("a passing look takes nothing", not agents.looking() and not agents.has_input(hand))
	await _seconds(agents.GAZE_ON + 0.1)
	_check("a held look gives the hand to the terminal", agents.looking() and agents.has_input(hand))
	fake.keys.clear()
	agents.on_stick(hand, Vector2(1, 0), 0.016)
	_check("the stick right is the arrow", fake.keys == ["Right"])
	agents.on_stick(hand, Vector2.ZERO, 0.016)
	agents.on_stick(hand, Vector2(-1, 0), 0.016)
	agents.on_stick(hand, Vector2.ZERO, 0.016)
	agents.on_stick(hand, Vector2(0.2, -1), 0.016)
	agents.on_stick(hand, Vector2.ZERO, 0.016)
	_check("left, and the stronger axis wins (%s)" % [fake.keys], fake.keys == ["Right", "Left", "Down"])
	fake.keys.clear()
	agents.on_trigger(hand, false)
	_check("the trigger is Enter", agents.on_trigger(hand, true) and fake.keys == ["Enter"])
	agents.on_trigger(hand, false)

	agents.on_stick(hand, Vector2(0, 1), 0.016)
	fake_gaze.gone = true
	await _seconds(agents.GAZE_OFF + 0.15)
	_check("a held stick keeps it past the look", agents.looking())
	agents.on_stick(hand, Vector2.ZERO, 0.016)
	await _seconds(agents.GAZE_OFF * 0.4)
	_check("a blink keeps it", agents.looking())
	await _seconds(agents.GAZE_OFF + 0.1)
	_check("a look away gives it back", not agents.looking() and not agents.has_input(hand))

	fake_gaze.gone = false
	fake_gaze.fitted = false
	await _seconds(agents.GAZE_ON + 0.1)
	_check("no calibration: the raw gaze looks too (a new install)", agents.looking() and agents.has_input(hand))
	_check("with the wider margin (%.1f, calibrated %.1f)" % [agents.GAZE_MARGIN_RAW_DEG, agents.GAZE_MARGIN_DEG],
			agents.gaze_margin() == agents.GAZE_MARGIN_RAW_DEG and agents.GAZE_MARGIN_RAW_DEG > agents.GAZE_MARGIN_DEG)
	# 4 degrees past the edge, seen from a metre: within the raw margin, past the calibrated one.
	var four := tan(deg_to_rad(4.0))
	_look_at_pane(pane, half.x + four, 0)
	_check("4 degrees off the edge meets it uncalibrated", pane.looked_at(fake_gaze.origin, fake_gaze.dir,
			agents.gaze_margin()))
	fake_gaze.fitted = true
	_check("but not calibrated", not pane.looked_at(fake_gaze.origin, fake_gaze.dir, agents.gaze_margin()))
	fake_gaze.fitted = false
	_look_at_pane(pane, half.x + tan(deg_to_rad(6.0)), 0)
	await _seconds(agents.GAZE_OFF + 0.15)
	_check("6 degrees off, uncalibrated: not looking", not agents.looking())
	_look_at_pane(pane, 0, 0)
	main.set_menu_shown(true)
	await _seconds(agents.GAZE_ON + 0.1)
	_check("the menu open: the look takes nothing from it", not agents.looking() and not agents.has_input(hand))
	main.set_menu_shown(false)
	fake_gaze.fitted = true
	await _seconds(agents.GAZE_ON + 0.1)
	_check("looking, calibrated", agents.looking())
	fake_gaze.calibrating = true
	await _seconds(agents.GAZE_OFF + 0.15)
	_check("nor while calibrating", not agents.looking())
	fake_gaze.calibrating = false
	await _seconds(agents.GAZE_ON + 0.1)
	_check("looking again", agents.looking())
	agents.gaze_override = null
	await _keyboard_checks()
	agents.hide_pane()
	await _frames(2)
	_check("a hidden pane drops it at once", not agents.looking())


func _key_event(code: Key, unicode: int, pressed := true, ctrl := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.unicode = unicode
	e.pressed = pressed
	e.ctrl_pressed = ctrl
	return e


## A window on the big screen as well: the look decides.
func _keyboard_window_checks() -> void:
	var pane: Node3D = agents.get_node("AgentPane")
	agents.window_override = true
	fake.typed = ""
	fake_gaze.gone = true
	agents.gaze_override = fake_gaze
	await _seconds(agents.GAZE_OFF + 0.1)
	_check("a window, and no look at the pane: the keyboard is the window's",
			not agents.looking() and not agents.on_key(_key_event(KEY_H, 104)) and fake.typed == "")
	agents.on_key(_key_event(KEY_H, 104, false))
	fake_gaze.gone = false
	_look_at_pane(pane, 0, 0)
	await _seconds(agents.GAZE_ON + 0.1)
	_check("a look at the pane takes it", agents.looking() and agents.on_key(_key_event(KEY_H, 104)) and fake.typed == "h")
	_check("the repeat follows the press", agents.on_key(_make_echo(KEY_H, 104)) and fake.typed == "hh")
	fake_gaze.gone = true
	await _seconds(agents.GAZE_OFF + 0.1)
	_check("the release follows the press past the look", agents.on_key(_key_event(KEY_H, 104, false)))
	_check("then the next key is the window's", not agents.on_key(_key_event(KEY_I, 105)))
	agents.window_override = false
	agents.gaze_override = null
	await _frames(2)
	_check("no window: the keyboard is the pane's with no look", agents.on_key(_key_event(KEY_J, 106)))
	agents.on_key(_key_event(KEY_J, 106, false))
	fake_gaze.gone = false


func _make_echo(code: Key, unicode: int) -> InputEventKey:
	var e := _key_event(code, unicode)
	e.echo = true
	return e


func _keyboard_checks() -> void:
	fake.typed = ""
	fake.keys.clear()
	_check("a keyboard types into the pane", agents.on_key(_key_event(KEY_H, 104)) and fake.typed == "h")
	_check("its release is taken, not typed", agents.on_key(_key_event(KEY_H, 104, false)) and fake.typed == "h")
	_check("Ctrl + a letter is a key", agents.on_key(_key_event(KEY_C, 99, true, true)) and fake.keys == ["C"])
	fake.keys.clear()
	_check("Backspace is a key", agents.on_key(_key_event(KEY_BACKSPACE, 0)) and fake.keys == ["Backspace"])
	_check("the player keeps its own keys", not agents.on_key(_key_event(KEY_F12, 0)))
	FileAccess.open(AgentTerminal.player_dir("claude").path_join("waiting"), FileAccess.WRITE).close()
	await _seconds(0.7)
	_check("a prompt waits", agents.waiting())
	agents.on_key(_key_event(KEY_ENTER, 0))
	_check("Enter on the keyboard answers it", not agents.waiting())
	for code: Key in [KEY_C, KEY_BACKSPACE, KEY_ENTER]:
		agents.on_key(_key_event(code, 0, false))
	await _keyboard_window_checks()
	agents.hide_pane()
	await _frames(2)
	_check("a hidden pane leaves the keyboard to the player", not agents.on_key(_key_event(KEY_H, 104)))
	agents.toggle_pane()
	await _frames(2)


## The mark as a hook writes it, between two looks of the app.
func _set_mark_now(id: String) -> void:
	agents._answered()
	FileAccess.open(AgentTerminal.player_dir(id).path_join("waiting"), FileAccess.WRITE).close()


func _input_checks() -> void:
	main.ui.hide_panel()
	await _frames(2)
	var hand: Node = main.ui.pointer_hand
	if hand == null:
		hand = main.right_hand
		main.ui.pointer_hand = hand
	fake.keys.clear()
	agents.on_trigger(hand, false)
	_check("no prompt, no squeeze: the trigger stays the film's", agents.on_trigger(hand, true) == false)
	_check("and the stick", agents.on_stick(hand, Vector2(0, 1), 0.016) == false and fake.keys.is_empty())
	hand.set("grip_down", true)
	_check("squeeze held: the trigger is Enter", agents.on_trigger(hand, true) and fake.keys == ["Enter"])
	_check("and its release doesn't reach the film", agents.on_trigger(hand, false))
	fake.keys.clear()
	agents.on_stick(hand, Vector2(0, 1), 0.016)
	_check("squeeze + stick scrolls back (%s)" % [fake.keys], fake.keys == ["Shift", "PageUp"])
	agents.on_stick(hand, Vector2.ZERO, 0.016)
	hand.set("grip_down", false)
	var w := FileAccess.open(AgentTerminal.player_dir("claude").path_join("waiting"), FileAccess.WRITE)
	w.close()
	await _seconds(0.7)
	fake.keys.clear()
	agents.on_stick(hand, Vector2(0, -1), 0.016)
	_check("a prompt waits: the stick is arrows", fake.keys == ["Down"])
	agents.on_stick(hand, Vector2.ZERO, 0.016)
	fake.keys.clear()
	_check("B is Escape", agents.on_button(hand, "prev_file") and fake.keys == ["Escape"])
	_check("and it clears the wait", not agents.waiting())
	w = FileAccess.open(AgentTerminal.player_dir("claude").path_join("waiting"), FileAccess.WRITE)
	w.close()
	await _seconds(0.7)
	agents.hide_pane()
	await _frames(2)
	_check("hidden pane: nothing is taken, even with a prompt waiting", not agents.has_input(hand)
			and agents.on_trigger(hand, true) == false)
	DirAccess.remove_absolute(AgentTerminal.player_dir("claude").path_join("waiting"))
	await _seconds(0.7)
	await _gaze_checks(hand)
	await _seconds(0.7)
	await _pane_fade_checks()
	await _y_checks(hand)
	# Talk: shows the pane; a tap while it shows hides it.
	agents.on_talk(true)
	_check("talk shows the pane", agents.pane_shown())
	agents.on_talk(false)
	_check("a press that showed it leaves it", agents.pane_shown())
	agents.on_talk(true)
	agents.on_talk(false)
	_check("a quick tap while it shows hides it", not agents.pane_shown())
	agents.on_talk(true)
	agents._talk_down -= LocalAgents.TAP_MSEC + 100
	agents.on_talk(false)
	_check("a long press (speech) leaves it showing", agents.pane_shown())
	await _x_checks(hand)


## X (the action map's "enter", the right controller): Enter whenever the terminal shows, whichever hand points, the
## menu open or not; its legend ENTER then, none otherwise.
func _x_checks(hand: Node) -> void:
	var right: Node = main.right_hand
	var texts := func() -> Dictionary: return right.visual.get("_texts")
	if not agents.pane_shown():
		agents.toggle_pane()
	await _frames(2)
	fake.keys.clear()
	_check("the pane shows: X is Enter", agents.enter_ready() and agents.on_enter_button(right) and fake.keys == ["Enter"])
	_check("no prompt, no look, no squeeze needed", not agents.has_input(hand))
	_check("its legend says ENTER (%s)" % texts.call().get("x", ""), texts.call().get("x", "") == "ENTER")
	main.ui.set_pointer_hand(main.left_hand)
	fake.keys.clear()
	_check("the left hand pointing: X is still Enter", agents.on_enter_button(right) and fake.keys == ["Enter"])
	main.ui.set_pointer_hand(main.right_hand)
	main.set_menu_shown(true)
	fake.keys.clear()
	_check("the menu open: X is still Enter, the legend too", agents.on_enter_button(right) and fake.keys == ["Enter"]
			and texts.call().get("x", "") == "ENTER")
	main.set_menu_shown(false)
	FileAccess.open(AgentTerminal.player_dir("claude").path_join("waiting"), FileAccess.WRITE).close()
	await _seconds(0.7)
	agents.on_enter_button(right)
	_check("X answers a waiting prompt", not agents.waiting())
	agents.hide_pane()
	await _frames(2)
	fake.keys.clear()
	_check("the pane hidden: X does nothing", not agents.enter_ready() and not agents.on_enter_button(right)
			and fake.keys.is_empty())
	_check("and its legend goes (%s)" % [texts.call()], not texts.call().has("x"))
	_check("the spoken enter stays", agents.spoken_key("Enter.") == "enter")
	agents.toggle_pane()
	await _frames(2)
	# The first start's introduction (ui/intro.gd) not gone through: the terminal takes no controller keys.
	main.ui.show_intro()
	await _frames(2)
	hand.set("grip_down", true)
	fake.keys.clear()
	_check("the introduction pending: no X, no squeeze keys, no keyboard", main.ui.intro_pending()
			and not agents.on_enter_button(right) and not agents.has_input(hand) and not agents.on_trigger(hand, true)
			and not agents.on_key(_key_event(KEY_H, 104)) and fake.keys.is_empty())
	hand.set("grip_down", false)
	main.ui.hide_panel()
	agents.on_agent_button(hand)
	_check("Y opens the menu at the introduction", main.ui.is_open() and main.ui.ui.intro_showing())
	main.ui.ui.intro.active = false
	main.ui.ui.intro.finished.emit()
	main.ui.hide_panel()
	await _frames(2)
	fake.keys.clear()
	_check("gone through: X is Enter again", agents.on_enter_button(right) and fake.keys == ["Enter"])


func _context_checks() -> void:
	main.current_path = "stub://flat_sbs"
	agents.deliver("hello")
	await _seconds(0.3)
	var text := FileAccess.get_file_as_string(AgentTerminal.player_dir("claude").path_join("context.txt"))
	_check("the context file: what plays and where (%s)" % text.strip_edges(), text.begins_with("[On the headset: ")
			and text.contains(" of ") and (text.contains("playing") or text.contains("paused")))
	main.current_path = ""
	# A sign-in link the agent asked a browser for.
	var card: Node = main.ui.get("card")
	var f := FileAccess.open(AgentTerminal.player_dir("claude").path_join("open_url"), FileAccess.WRITE)
	f.store_string("https://claude.ai/oauth/authorize?x=1\n")
	f.close()
	await _seconds(0.8)
	_check("a link it wants opened comes as a card (%s)" % card.get("_text").text, card.is_showing()
			and str(card.get("_text").text).contains("Claude Code wants to open claude.ai/oauth"))
	card.dismiss("no")
	await _frames(2)


## The terminal starts outside the app's process tree where the user's service manager is there (Steam's launch wrapper
## would wait for it); elsewhere as it is.
## The terminals' own display (2026-11-10): under gamescope a terminal on the game's display is forwarded to SteamVR
## too, and killed its compositor. There they go to an X server gamescope never sees.
func _display_checks() -> void:
	AgentTerminal.display_override = "desktop"
	_check("display: the desktop's own elsewhere", AgentTerminal.display() == "" and AgentTerminal.wait_display())
	var plain: Array = AgentTerminal.detached("/usr/bin/xterm", [], "claude")
	AgentTerminal.display_override = "private"
	_check("display: a private one under gamescope", AgentTerminal.display() == ":%d" % AgentTerminal.DISPLAY_NUMBER)
	var cmd: Array = AgentTerminal.detached("/usr/bin/xterm", [], "claude")
	if str(cmd[0]) != "/usr/bin/xterm":
		var envs: Array = (cmd[1] as Array).filter(func(a: String) -> bool: return a.begins_with("--setenv="))
		_check("display: the terminal gets the private display, once", envs.count("--setenv=DISPLAY=" + AgentTerminal.display()) == 1
				and envs.filter(func(a: String) -> bool: return a.begins_with("--setenv=DISPLAY=")).size() == 1)
		_check("display: and nothing of the session's Wayland or X cookie", not envs.any(func(a: String) -> bool:
			return a.begins_with("--setenv=WAYLAND_DISPLAY=") or a.begins_with("--setenv=XAUTHORITY=")))
		_check("display: the desktop case keeps the session's display", not (plain[1] as Array).has(
				"--setenv=DISPLAY=" + AgentTerminal.display()))
	var script := AgentTerminal.display_script()
	_check("display: the server takes no network clients and starts locked", script.contains("-nolisten tcp")
			and script.contains("-auth \"$auth\"") and script.contains("umask 077"))
	_check("display: only this user is let in, then it says ready", script.find("+SI:localuser:") > script.find("Xvfb")
			and script.find(": > \"$ready\"") > script.find("+SI:localuser:"))
	# From a file: OS.execute() with output goes through a shell, which would mangle the script's own $ and quotes.
	var file := OS.get_cache_dir().path_join("framecine-display-test.sh")
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string(script)
	f.close()
	_check("display: the script is valid shell", OS.execute("/bin/sh", ["-n", file]) == 0)
	DirAccess.remove_absolute(file)
	AgentTerminal.display_override = ""


## The terminal's window (the user, 2026-11-10: off the controller, a window that floats): it comes up ahead of the
## head facing it, and is held and sized as a PC window's pane.
func _window_checks() -> void:
	var pane: Node3D = agents._pane
	var cam: Node3D = main.camera
	pane.placed = false
	pane.set_shown(true)
	var ahead := -cam.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var want: Vector3 = ahead * LocalAgents.AgentPane.DISTANCE_M + Vector3.DOWN * LocalAgents.AgentPane.DROP_M
	var to: Vector3 = pane.global_position - cam.global_position
	_check("window: comes up ahead of the head, a little low (%.2f m)" % to.length(), pane.placed
			and to.distance_to(want) < 0.001)
	var flat_back := -to
	flat_back.y = 0.0
	_check("window: faces the head, level", pane.global_basis.z.dot(flat_back.normalized()) > 0.999
			and absf(pane.global_basis.x.y) < 0.001)
	var hand := FakeHand.new()
	root.add_child(hand)
	hand.global_position = cam.global_position + Vector3(0.15, -0.3, 0.0)
	hand.look_at(pane.global_position, Vector3.UP)
	var d := hand.global_position.distance_to(pane.global_position)
	var aim: Dictionary = pane.hit(hand.get_ray_origin(), hand.get_ray_direction())
	_check("window: a laser meets it (%s)" % [aim], not aim.is_empty() and absf(float(aim["distance"]) - d) < 0.01)
	var away := FakeHand.new()
	root.add_child(away)
	away.global_position = hand.global_position
	away.look_at(hand.global_position + Vector3.UP, Vector3.BACK)
	_check("window: a laser pointing away misses it", pane.hit(away.get_ray_origin(), away.get_ray_direction()).is_empty())
	away.free()
	agents._aims[hand] = aim
	_check("window: the squeeze leaves it alone now", not agents.on_grip(hand, true) and not agents.holding(hand))
	# Its frame (docs/dev/surfaces-design.md): the title bar over the picture, Close at its end, Enter and Esc beside.
	var bar: float = pane.frame.bar_height()
	var top: Vector3 = pane.global_position + pane.global_basis.y * (float(pane._height) / 2.0 + bar / 2.0)
	var from: Vector3 = top + pane.global_basis.z
	var on_bar: Dictionary = pane.hit(from, -pane.global_basis.z)
	_check("window: the title bar is over the picture (%s)" % [on_bar], str(on_bar.get("part", "")) == "bar")
	var close: Dictionary = pane.hit(from + pane.global_basis.x * (pane.width / 2.0 - bar), -pane.global_basis.z)
	_check("window: Close at the bar's right end", str(close.get("part", "")) == "close")
	var enter: Dictionary = pane.hit(from + pane.global_basis.x * (pane.width / 2.0 + bar), -pane.global_basis.z)
	var esc: Dictionary = pane.hit(from + pane.global_basis.x * (pane.width / 2.0 + bar) - pane.global_basis.y * bar,
			-pane.global_basis.z)
	_check("window: Enter and Esc in the stack beside it (%s, %s)" % [enter.get("id"), esc.get("id")],
			str(enter.get("id", "")) == "enter" and str(esc.get("id", "")) == "escape")
	main.pointing.select(null)
	_check("window: the trigger on the picture selects it and is not kept by the frame",
			not agents._frame_trigger(hand, true) and agents.is_selected())
	main.pointing.select(null)
	agents._aims[hand] = {"distance": d, "part": "bar"}
	_check("window: the trigger on the title bar takes it and selects it", agents.on_trigger(hand, true)
			and agents.holding(hand) and agents.owns_laser(hand) and agents.is_selected() and agents.point_holds(hand))
	hand.rotate_y(deg_to_rad(15.0))
	agents._hold(hand)
	_check("window: it rides the ray", pane.global_position.distance_to(hand.get_ray_origin()
			+ hand.get_ray_direction() * d) < 0.001)
	_check("window: held, it stays level", absf(pane.global_basis.x.y) < 0.001)
	var w: float = pane.width
	agents.on_stick(hand, Vector2(1.0, 0.0), 0.5)
	_check("window: stick right while holding, bigger (%.2f to %.2f)" % [w, pane.width], pane.width > w)
	agents.on_stick(hand, Vector2(0.0, 1.0), 0.5)
	_check("window: stick up while holding, further", float(agents._holds[hand]["distance"]) > d)
	_check("window: while held, the stick isn't the terminal's", not agents.has_input(hand))
	_check("window: the trigger up lets go", agents.on_trigger(hand, false))
	_check("window: let go; its width is kept", not agents.holding(hand)
			and absf(float(main.settings.get_value("agent_window", "width", 0.0)) - snappedf(pane.width, 0.01)) < 0.001)
	pane.set_width(100.0)
	_check("window: the width has limits", pane.width == LocalAgents.AgentPane.MAX_WIDTH_M)
	agents._aims.erase(hand)
	hand.free()
	pane.set_width(LocalAgents.AgentPane.WIDTH_M)
	agents.hide_pane()
	_check("window: hidden, it is not the selection", not agents.is_selected())


func _detached_checks() -> void:
	var kept := OS.get_environment("XDG_RUNTIME_DIR")
	var args: Array[String] = ["-class", "frame-claude", "-e", "/bin/sh", "run.sh"]
	OS.unset_environment("XDG_RUNTIME_DIR")
	var plain: Array = AgentTerminal.detached("/usr/bin/xterm", args, "claude")
	_check("no runtime dir: the terminal as it is", plain[0] == "/usr/bin/xterm" and plain[1] == args)
	if FileAccess.file_exists("/usr/bin/systemd-run"):
		OS.set_environment("XDG_RUNTIME_DIR", "/tmp")
		var d: Array = AgentTerminal.detached("/usr/bin/xterm", args, "claude")
		var da: Array = d[1]
		_check("a runtime dir and systemd-run: a transient user unit, the terminal after --", d[0] == "/usr/bin/systemd-run"
				and da[0] == "--user" and "--collect" in da and str(da[3]).begins_with("--unit=frame-claude-")
				and da.slice(da.find("--") + 1) == ["/usr/bin/xterm"] + args
				and "--setenv=XDG_RUNTIME_DIR=/tmp" in da)
	if kept == "":
		OS.unset_environment("XDG_RUNTIME_DIR")
	else:
		OS.set_environment("XDG_RUNTIME_DIR", kept)


## The terminal needs a UTF-8 locale: LC_ALL wins over LANG, and the Frame's Steam sets it to C.
func _locale_checks() -> void:
	var kept := {}
	for v in ["LC_ALL", "LC_CTYPE", "LANG"]:
		kept[v] = OS.get_environment(v)
		OS.unset_environment(v)
	_check("no locale: not UTF-8", not AgentTerminal._utf8_locale())
	OS.set_environment("LANG", "en_US.UTF-8")
	_check("LANG UTF-8: fine", AgentTerminal._utf8_locale())
	OS.set_environment("LC_ALL", "C")
	_check("LC_ALL=C wins over LANG: not UTF-8", not AgentTerminal._utf8_locale())
	OS.set_environment("LC_ALL", "C.UTF-8")
	_check("LC_ALL=C.UTF-8: fine", AgentTerminal._utf8_locale())
	for v in kept:
		if str(kept[v]) == "":
			OS.unset_environment(v)
		else:
			OS.set_environment(v, str(kept[v]))


func _small_checks() -> void:
	var quad: MeshInstance3D = agents.get_node("AgentPane/AgentQuad")
	_check("the pane is on the private layer", quad.get_layer_mask_value(VideoScreen.PRIVATE_LAYER)
			and not quad.get_layer_mask_value(1))
	var snap := RoomSnapshot.new()
	root.add_child(snap)
	var cam: Camera3D = snap.get("_camera")
	_check("the snapshots for assistants don't see it", not cam.get_cull_mask_value(VideoScreen.PRIVATE_LAYER))
	snap.free()
	var src := WindowVideoSource.new()
	src.path = "terminal://claude"
	src.terminal_id = "claude"
	_check("a terminal is not a browser", not src.is_browser() and src.is_terminal())
	_check("its title is the agent's name, whatever the window says", src._read_title() == "Claude Code")
	_check("a terminal path is a window path", WindowVideoSource.is_window_path("terminal://claude"))
	var labels: Dictionary = main.controller_labels(main.PREVIEW_PROFILE, "right", false, false, true)
	_check("the labels while the terminal has the input (%s)" % [labels], str(labels.values()).contains("ENTER")
			and str(labels.values()).contains("ESC"))
	var places: Array = preload("res://ui/files_tab.gd").get_places()
	_check("Claude Code and Codex are in the places", places.any(func(p: Dictionary) -> bool:
			return p["path"] == "agent://claude" and p["label"] == "Claude Code") and places.any(func(p: Dictionary) -> bool:
			return p["path"] == "agent://codex" and p["label"] == "Codex"))
	_check("the assistant link can't open a terminal", preload("res://scripts/assistant/assistant_commands.gd")
			.open_refusal("terminal://claude") != "")
	var files: Node = main.ui.ui.files
	files.open_folder("agent://claude")
	var rows: Array = files.get("_rows")
	_check("the entry's rows: the second action is the big screen", rows.any(func(r: Dictionary) -> bool:
			return r["kind"] == "agent_screen"))
	_check("a running agent: both starts are just Show", rows.any(func(r: Dictionary) -> bool:
			return r["kind"] == "agent_pane" and str(r["text"]) == "Show the window")
			and not rows.any(func(r: Dictionary) -> bool: return r["kind"] == "agent_plain"))
	_check("a running agent: restart, briefed or plain", rows.any(func(r: Dictionary) -> bool:
			return r["kind"] == "agent_restart") and rows.any(func(r: Dictionary) -> bool:
			return r["kind"] == "agent_restart_plain"))
	await _restart_checks()
	fake.windows.clear()
	agents._refresh_running()
	files.open_folder("agent://claude")
	rows = files.get("_rows")
	_check("not running: briefed or plain", rows.any(func(r: Dictionary) -> bool: return r["kind"] == "agent_plain")
			and rows.any(func(r: Dictionary) -> bool: return str(r["text"]) == "Start, briefed on the player"))


## The window goes as the terminal would, the new one comes from the start.
func _restart_checks() -> void:
	var window: Dictionary = fake.windows[0]
	var waiting_mark := AgentTerminal.player_dir("claude").path_join("waiting")
	agents.restart_agent("claude", true)
	await _frames(2)
	_check("a restart waits for the old window", FileAccess.get_file_as_string(
			AgentTerminal.player_dir("claude").path_join("run.sh")).contains("--continue"))
	fake.windows.clear()
	await _seconds(0.25)
	var run := FileAccess.get_file_as_string(AgentTerminal.player_dir("claude").path_join("run.sh"))
	_check("restart plain: no briefing, nothing continued", not run.contains("P='") and not run.contains("--continue"))
	_check("no trust question is expected", not FileAccess.file_exists(waiting_mark))
	_check("it stays the active agent", agents.active == "claude")
	fake.windows.append(window)
	await _seconds(0.7)
	_check("the new window is on the pane", agents.is_running("claude") and fake.captured == int(window["id"]))
	agents.restart_agent("claude")
	await _frames(2)
	fake.windows.clear()
	await _seconds(0.25)
	run = FileAccess.get_file_as_string(AgentTerminal.player_dir("claude").path_join("run.sh"))
	_check("restart briefed: the briefing, nothing continued", run.contains("P='") and not run.contains("--continue"))
	fake.windows.append(window)
	await _seconds(0.7)


func _clear(p: String) -> void:
	var d := DirAccess.open(p)
	if d == null:
		return
	d.include_hidden = true
	for sub in d.get_directories():
		_clear(p.path_join(sub))
	for f in d.get_files():
		DirAccess.remove_absolute(p.path_join(f))
	DirAccess.remove_absolute(p)


func _seconds(s: float) -> void:
	var end := Time.get_ticks_msec() + int(s * 1000.0)
	while Time.get_ticks_msec() < end:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(what: String, ok: bool) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		print("FAIL " + what)
