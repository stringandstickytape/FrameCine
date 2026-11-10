extends RefCounted

## The AI agents that run on the headset itself, each in its own terminal window on the desktop's X display (docs/
## assistant.md, "Agents on the headset"). AGENTS is the table: add a row for another agent. This file knows what is on
## disk and how to start a terminal; scripts/agents/local_agents.gd is the running side (the pane, voice, keys).
##
## Each agent has a working folder of its own (~/Claude, ~/Codex) with an instructions file the app writes once (never
## over the user's), hook settings merged into the agent's own (never replacing the user's), and a folder .player/ with
## what the app and the agent's hooks share:
##   run.sh       what the terminal runs (full paths: the desktop session's PATH may not have ~/.local/bin)
##   hook.sh      the agent's hooks: prompt (prints the context, a few ms: a shell builtin and cat), waiting, clear
##   context.txt  what the viewer is watching, kept up to date by the app; the hook prints it into every message
##   waiting      exists while the agent waits on a permission or choice prompt (the app polls it)
##   hook_seen    the prompt hook has run at least once (Codex runs a hook only after /hooks trusts it)
##   open_url     links the agent asked a browser for (bin/xdg-open, $BROWSER), for the app to offer
##   started      this folder has had a session: a new terminal continues it instead of briefing again
##   mcp/         the player's MCP adapter and its helper (res://assistant/tools/), for the agent's MCP config
## and .assistant-link in the working folder (mode 600), a curl config with the agent's token and the headset's pin
## for the player's API: `curl -K .assistant-link https://127.0.0.1:47802/state`, so no token on a command line. The
## viewer picking the entry is the consent, so there is no pairing code (assistant_service.pair_local); forgetting
## the assistant in the System tab deletes the file.
## The player's tools reach the agent as an MCP server, MCP_NAME, declared where the agent looks for this folder's
## servers (Claude Code: .mcp.json, and the server enabled by name in .claude/settings.json, which counts only once the
## viewer has trusted the folder; Codex: .codex/config.toml, read only in a trusted folder, in a marked block the app
## owns). The agent starts python3 with mcp/mcp_server.py, the API's address and the link file as its config: the token
## is in neither the config nor any command line. No tool is allowed ahead: the agent asks before each, as for anything.
## No network, so no authentication: these are the user's own files in the user's own folder (mode 700). The agents'
## credentials are theirs: only whether a credentials file exists is looked at, never its contents.
##
## The terminal is found by its window class, not a pid, so it survives the player: nothing here ever closes it.
##
## Why xterm first: one process per window (konsole and lxterminal hand a new window to a running instance unless told
## not to), no tab bar or menu to hide, sized exactly in cells with a font given in pixels (FONT_PX is the same on any
## display, whatever its DPI setting), and a class given on the command line. Text through Xft is antialiased and crisp;
## allowTitleOps off keeps the agent's words out of the window's title. It must be told to accept the window capture's
## synthetic keys (allowSendEvents), which any X client of this user could send anyway on this single-user device.

const AGENTS := {
	"claude": {
		"name": "Claude Code", "binary": "claude", "folder": "Claude", "class": "frame-claude",
		"client": "Claude Code on this headset",
		# An interactive session goes on from the last one in this folder (`claude -c`).
		"continue": "--continue",
		"binaries": [".local/bin/claude", ".claude/local/claude", "/usr/local/bin/claude", "/usr/bin/claude"],
		# Only checked to exist, never read.
		"credentials": ".claude/.credentials.json",
		"instructions": "CLAUDE.md", "hooks_file": ".claude/settings.json",
		# The project's MCP servers; enabledMcpjsonServers in its settings names ours, so once the folder is trusted
		# Claude Code uses it without asking. Its tools still ask, each in turn.
		"mcp_file": ".mcp.json", "mcp_enable": "enabledMcpjsonServers",
		"install": "curl -fsSL https://claude.ai/install.sh | bash",
		"sign_in": "",
		"keys": {"yes": "1", "no": "escape"},
		# The context reaches it by the hook alone.
		"inline_context": false,
	},
	"codex": {
		"name": "Codex", "binary": "codex", "folder": "Codex", "class": "frame-codex",
		"client": "Codex on this headset",
		"continue": "resume --last",
		"binaries": [".local/bin/codex", "/usr/local/bin/codex", "/usr/bin/codex"],
		"credentials": ".codex/auth.json",
		"instructions": "AGENTS.md", "hooks_file": ".codex/hooks.json",
		# The project's config: its MCP servers are [mcp_servers.<name>] tables.
		"mcp_file": ".codex/config.toml", "mcp_enable": "",
		# The standalone release for this machine (there is no Node on the Frame).
		"install": "a=$(uname -m); case \"$a\" in arm64) a=aarch64;; esac; t=$(mktemp -d); curl -fsSL " \
				+ "\"https://github.com/openai/codex/releases/latest/download/codex-$a-unknown-linux-musl.tar.gz\" " \
				+ "| tar -xz -C \"$t\" && mkdir -p \"$HOME/.local/bin\" && mv \"$t\"/codex-* " \
				+ "\"$HOME/.local/bin/codex\" && chmod +x \"$HOME/.local/bin/codex\"; rm -rf \"$t\"",
		"sign_in": "\"$BIN\" login status >/dev/null 2>&1 || \"$BIN\" login --device-auth",
		"keys": {"yes": "y", "no": "n"},
		# Codex runs a hook only once the viewer has trusted it with /hooks: until the hook has run, a short bracketed
		# context line goes ahead of the spoken words.
		"inline_context": true,
	},
}
const TERMINALS: Array[String] = ["xterm", "konsole", "lxterminal"]
## The window. The Frame's window manager (gamescope) makes every top-level window 1920 x 1080 whatever it asks for
## (seen on the headset, 2026-11-01), so the size asked for only matters elsewhere: FONT_PX sets what fits there. At
## 28 px a DejaVu Sans Mono cell is 17 x 33 pixels, so the 1904 x 1064 inside the border holds 112 columns by 32 lines:
## room for Claude Code's first-run theme preview (about 100 columns) and both agents' 80-column screens, with the
## lines to show a whole list. 40 px held 79 x 22, and Claude Code's first screen did not fit (the user, 2026-11-09).
## In its window (WIDTH_M, 60 cm at 90 cm, in agent_pane.gd) a 28 px em is 0.56 degrees, a capital 0.41, an x 0.31,
## a line 0.66 (40 px on the 26 cm pane was 0.69, 0.50, 0.38, 0.83); nearer, more.
const COLUMNS := 112
const LINES := 32
const FONT_PX := 28
const BACKGROUND := "#0d1117"
const FOREGROUND := "#e6edf3"
const SCROLLBACK := 10000
const PLAYER_DIR := ".player"
const LINK_FILE := ".assistant-link"
## The player's MCP server: its name in the agent's config (the agent's tools are mcp__vr-player__<command>), the
## folder under .player/ it is copied to, and where it comes from (the same files the service serves at /tools/).
const MCP_NAME := "vr-player"
const MCP_DIR := "mcp"
const MCP_SOURCE := "res://assistant/tools"
const MCP_FILES: Array[String] = ["mcp_server.py", "assistant.py"]
## Codex's config is TOML: the app's table lies between these lines, at the end of the file, so the user's lines above
## it stay in their own tables.
const TOML_BEGIN := "# VR player: begin. The player rewrites this part when it starts you; add your own settings " \
		+ "above it."
const TOML_END := "# VR player: end"
## The player's own ports (assistant_service.gd), from the headset itself.
const API_URL := "https://127.0.0.1:47802"
const GUIDE_URL := "http://127.0.0.1:47801/"
## The app's part of an instructions file lies between these lines: it is replaced when its text changes.
const BLOCK_BEGIN := "<!-- VR player: begin. The player rewrites this part when it starts you; add your own notes "\
		+ "outside it. -->"
const BLOCK_END := "<!-- VR player: end -->"
## In every session's instructions, so short: what the words mean, where things go, and that a share is the player's to
## read. The rest is "The Library" in the guide (res://assistant/library.md).
const LIBRARY_NOTES := """
## The Library: ~/Videos/Library

"Import" or "add to the library" means: copy it there under the right name and write its info files. "Info files" means
its .nfo and artwork. Do that without asking what they mean.

- Show: `TV Shows/<Show> (<Year>)/` holds `tvshow.nfo`, `poster.jpg`, `fanart.jpg`.
- Episode: `TV Shows/<Show> (<Year>)/Season 01/<Show> - S01E01 - <Title>.<ext>`, and beside it `<same name>.nfo` and
  `<same name>-thumb.jpg`.
- Film: `Movies/<Title> (<Year>)/<Title> (<Year>).<ext>`, `<Title> (<Year>).nfo`, `poster.jpg`, `fanart.jpg`.
- Look the year up; never guess it.

Network shares go through the player only, with the login it holds. Never mount a share, never use gio, smbclient or
mount, never ask for or read a share's password, never touch ~/.smb-password. A login error means you went round the
player: use its `list_dir` and `copy_to_library` tools, or these (`to` is relative to the Library).

```
curl -s -K <<LINK>> <<API>>/command -d cmd=list_dir --data-urlencode "path=network://"
curl -s -K <<LINK>> <<API>>/command -d cmd=list_dir -d all=true --data-urlencode "path=<an entry's path>"
curl -s -K <<LINK>> <<API>>/command -d cmd=copy_to_library --data-urlencode "from=<an entry's path>" --data-urlencode "to=TV Shows/..."
```

One copy at a time: `library_copy` in /state shows it, null when done. A refused command names the switch it needs
(`switch` in the reply; copies need "Let the assistant manage files"): ask the viewer to turn it on in System, Assistant.

What an NFO holds, picture sizes, and where plots and art come from: "The Library" in the guide.
"""
## Lines of earlier versions of instructions_text(), now changed: gone with the rest of the app's text.
const OLD_LINES: Array[String] = [
	"- About 66 columns and 34 lines are visible at once: keep answers short and don't print long output.",
]
## The first message of a briefed session: an interactive session with an initial prompt, not -p (which exits).
## No secrets here: it is on a command line. No apostrophes: run.sh quotes it.
const BRIEFING := "Read " + GUIDE_URL + " (the guide of the video player you run in). You are paired already: " \
		+ "the player is yours through the tools of the MCP server " + MCP_NAME + ", so use them first, get_status " \
		+ "to begin. Without them, " + LINK_FILE + " in this folder is a curl config with your token and the pin: " \
		+ "curl -K " + LINK_FILE + " " + API_URL + "/state, and never put the token on a command line. Get ready, " \
		+ "say one line when you are, then wait for the viewer."

## Tests: another home folder; a terminal command (the xterm line's arguments follow it).
static var home_override := ""
static var terminal_override: Array[String] = []


static func home() -> String:
	if home_override != "":
		return home_override
	var h := OS.get_environment("HOME")
	return h if h != "" else OS.get_environment("USERPROFILE").replace("\\", "/")


static func folder(id: String) -> String:
	return home().path_join(str(AGENTS[id]["folder"]))


static func player_dir(id: String) -> String:
	return folder(id).path_join(PLAYER_DIR)


## The agent's program by full path, or "".
static func binary(id: String) -> String:
	for b: String in AGENTS[id]["binaries"]:
		var p := b if b.is_absolute_path() else home().path_join(b)
		if FileAccess.file_exists(p):
			return p
	return ""


static func installed(id: String) -> bool:
	return binary(id) != ""


## A credentials file exists (its contents are never read). A hint for the docs and the Files entry: the agent's own
## sign-in flow decides.
static func signed_in(id: String) -> bool:
	return FileAccess.file_exists(home().path_join(str(AGENTS[id]["credentials"])))


## What the app wants in the instructions file, as lines the block below holds.
static func instructions_text(id: String) -> String:
	var a: Dictionary = AGENTS[id]
	return "# You are running inside a VR video player, on the headset\n\n" \
			+ "This is a Valve Steam Frame. %s runs here in a terminal shown on a small pane on the viewer's controller, " \
			% a["name"] + "while a film may be playing on the big screen.\n\n" \
			+ "- The viewer wears the headset and mostly speaks: each message is speech to text, so expect the odd " \
			+ "wrong word.\n" \
			+ "- About %d columns and %d lines are visible at once: keep answers short and don't print long output.\n" \
			% [COLUMNS, LINES] \
			+ "- A message may come with what is playing (title, position, the last subtitle lines).\n" \
			+ "- The player's assistant guide is at %s : read it to control the player and to build rooms.\n" \
			% GUIDE_URL \
			+ "- The player's tools are the MCP server `%s` (in %s here): use them first, `get_status` to begin. " \
			% [MCP_NAME, a["mcp_file"]] + "The viewer talks to you here, so skip `wait_for_viewer_message` and " \
			+ "`answer_viewer`.\n" \
			+ "- Without them, curl: %s here is a curl config with your token and the pin. Use `curl -K %s " \
			% [LINK_FILE, LINK_FILE] + "%s/state`; never put the token on a command line or print it.\n" % API_URL \
			+ "- What you may do through the API follows the viewer's switches (System, Assistant): `control_allowed` " \
			+ "and `room_allowed` in GET /status.\n" \
			+ "- To get a video here, skip the guide's fetch step: download straight into `~/Videos/From assistant` " \
			+ "(mkdir -p it, keep 2 GB of the disk free), then `open` the file by its full path (needs " \
			+ "`control_allowed`).\n" \
			+ "- In ~/.local/bin: yt-dlp, with deno as its JavaScript runtime, and get_iplayer. ffmpeg and ffprobe are in " \
			+ "/usr/bin.\n" \
			+ "- Formats: VP9 8-bit or H.264 up to 2160p, which the headset decodes well; not AV1, not VP9 10-bit or HDR. " \
			+ "Merge to mkv: `yt-dlp -f \"bv*[vcodec^=vp09][dynamic_range=SDR][height<=2160]+ba/" \
			+ "bv*[vcodec^=avc1][height<=2160]+ba\" --merge-output-format mkv -P \"$HOME/Videos/From assistant\" " \
			+ "-o \"%(title)s.%(ext)s\" URL`.\n" \
			+ "- A 360 video: put `_360` at the end of the name, and check it is equirectangular, not the equi-angular " \
			+ "cubemap YouTube also serves (yt-dlp's format list and ffprobe's `spherical` side data say which; convert " \
			+ "EAC with ffmpeg's `v360=eac:e` first).\n" \
			+ LIBRARY_NOTES.replace("<<API>>", API_URL).replace("<<LINK>>", LINK_FILE)


## The instructions file with the app's block up to date and everything else kept. The block is what the app owns, so its
## text can change with the app; a file written before there was one (its lines exactly as the app wrote them) loses those
## lines, and any line the user added or changed stays, after the block.
static func merged_instructions(existing: String, id: String) -> String:
	var block := BLOCK_BEGIN + "\n" + instructions_text(id) + BLOCK_END + "\n"
	var from := existing.find(BLOCK_BEGIN)
	var to := existing.find(BLOCK_END)
	if from >= 0 and to > from:
		var after := existing.substr(to + BLOCK_END.length()).trim_prefix("\n")
		return existing.left(from) + block + after
	var own := {}
	for line in instructions_text(id).split("\n"):
		own[line] = true
	for line: String in OLD_LINES:
		own[line] = true
	var kept: PackedStringArray = []
	for line in existing.split("\n"):
		if not own.has(line):
			kept.append(line)
	var rest := "\n".join(kept).strip_edges()
	return block + ("\n" + rest + "\n" if rest != "" else "")


## The hook script: drains stdin, then does its one thing with shell builtins and cat, so a hook takes a few ms.
static func hook_text() -> String:
	return "#!/bin/sh\n# Written by the VR video player. The agent's hooks call it: see docs/assistant.md.\n" \
			+ "d=\"${0%/*}\"\ncat >/dev/null\ncase \"$1\" in\n" \
			+ "prompt) rm -f \"$d/waiting\"; : >\"$d/hook_seen\"; cat \"$d/context.txt\" 2>/dev/null ;;\n" \
			+ "waiting) : >\"$d/waiting\" ;;\nclear) rm -f \"$d/waiting\" ;;\nesac\nexit 0\n"


## event -> [[matcher, hook.sh's argument], ...]. Claude Code: PermissionRequest fires as the prompt appears (the
## Notification event only after about six idle seconds), AskUserQuestion is its choice prompt. Codex: the same
## event names for what it has (https://learn.chatgpt.com/docs/hooks).
static func hook_events(id: String) -> Dictionary:
	if id == "claude":
		return {"UserPromptSubmit": [["", "prompt"]], "PermissionRequest": [["", "waiting"]],
				"PreToolUse": [["AskUserQuestion", "waiting"]], "Notification": [["elicitation_dialog", "waiting"]],
				"PostToolUse": [["", "clear"]], "PostToolUseFailure": [["", "clear"]], "Stop": [["", "clear"]]}
	return {"UserPromptSubmit": [["", "prompt"]], "PermissionRequest": [["", "waiting"]],
			"PostToolUse": [["", "clear"]], "Stop": [["", "clear"]]}


## The agent's settings with our hooks and, for Claude Code, our MCP server enabled by name: everything the user has
## stays (a server they turned off stays off), and running it again changes nothing.
static func merged_settings(existing: Dictionary, id: String) -> Dictionary:
	var out := merged_hooks(existing, id)
	var key := str(AGENTS[id].get("mcp_enable", ""))
	if key != "":
		var names: Array = out[key].duplicate() if out.get(key) is Array else []
		if not names.has(MCP_NAME):
			names.append(MCP_NAME)
			out[key] = names
	return out


## The agent's hook settings with ours added: everything the user has stays, and running it again changes nothing.
static func merged_hooks(existing: Dictionary, id: String) -> Dictionary:
	var out := existing.duplicate(true)
	if not (out.get("hooks") is Dictionary):
		out["hooks"] = {}
	var script := player_dir(id).path_join("hook.sh")
	var events := hook_events(id)
	for event: String in events:
		if not (out["hooks"].get(event) is Array):
			out["hooks"][event] = []
		for entry: Array in events[event]:
			var command := "'%s' %s" % [script, entry[1]]
			if _has_command(out["hooks"][event], command):
				continue
			var group := {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
			if str(entry[0]) != "":
				group["matcher"] = entry[0]
			out["hooks"][event].append(group)
	return out


static func _has_command(groups: Array, command: String) -> bool:
	for group: Variant in groups:
		if group is Dictionary and group.get("hooks") is Array:
			for h: Variant in group["hooks"]:
				if h is Dictionary and str(h.get("command", "")) == command:
					return true
	return false


## What the terminal runs. install: the agent's installer first. plain: the agent just starts and waits, with no
## briefing. fresh: a new session with the briefing, whatever came before. Otherwise a new folder gets the briefing, and
## a folder that has had a session continues the last one (a terminal that had to be restarted), or starts afresh with
## the briefing if there is nothing to continue.
static func run_text(id: String, install := false, plain := false, fresh := false) -> String:
	var a: Dictionary = AGENTS[id]
	var dir := player_dir(id)
	var bin := binary(id)
	if bin == "":
		bin = home().path_join(str(a["binaries"][0]))
	var s := "#!/bin/sh\n# Written by the VR video player. The agent's own approval prompts stay on.\n"
	s += "cd '%s'\nexport PATH='%s/bin':\"$HOME/.local/bin:$PATH\"\nexport BROWSER='%s/bin/xdg-open'\n" % [folder(id), dir,
			dir]
	# The desktop session doesn't read ~/.bashrc: get_iplayer's Perl modules, as there.
	s += "export PERL5LIB=\"$HOME/perl5/lib/perl5${PERL5LIB:+:$PERL5LIB}\"\n"
	s += "BIN='%s'\n" % bin
	if install:
		s += "echo 'Installing %s ...'\n%s\n" % [a["name"], a["install"]]
	s += "if [ -x \"$BIN\" ]; then\n"
	if str(a["sign_in"]) != "":
		s += "  %s\n" % a["sign_in"]
	if plain:
		s += "  \"$BIN\"\n"
	else:
		s += "  P='%s'\n" % BRIEFING
		if fresh:
			s += "  : >'%s/started'\n  \"$BIN\" \"$P\"\n" % dir
		else:
			s += "  if [ -e '%s/started' ]; then\n    \"$BIN\" %s || \"$BIN\" \"$P\"\n  else\n" % [dir, a["continue"]]
			s += "    : >'%s/started'\n    \"$BIN\" \"$P\"\n  fi\n" % dir
	s += "else\n  echo '%s is not installed.'\nfi\n" % a["name"]
	s += "echo\necho '%s has ended. Press Enter to close this window.'\nread x\n" % a["name"]
	return s


## How the agent starts the player's MCP server: python3, the adapter in .player/mcp/, the API's address and the link
## file as its config. No secret: the token stays in the link file (mode 600).
static func mcp_command(id: String) -> Array[String]:
	var python := "/usr/bin/python3" if FileAccess.file_exists("/usr/bin/python3") else "python3"
	return [python, player_dir(id).path_join(MCP_DIR).path_join("mcp_server.py"), "--url", API_URL, "--config",
			link_path(id)]


## A project .mcp.json with our server added or brought up to date; the user's servers stay.
static func merged_mcp_json(existing: Dictionary, id: String) -> Dictionary:
	var out := existing.duplicate(true)
	if not (out.get("mcpServers") is Dictionary):
		out["mcpServers"] = {}
	var command := mcp_command(id)
	out["mcpServers"][MCP_NAME] = {"type": "stdio", "command": command[0], "args": command.slice(1)}
	return out


## The app's block in Codex's config.toml: our server's table.
static func codex_block(id: String) -> String:
	var command := mcp_command(id)
	return TOML_BEGIN + "\n[mcp_servers.%s]\ncommand = %s\nargs = %s\n" % [MCP_NAME, JSON.stringify(command[0]),
			JSON.stringify(command.slice(1))] \
			+ "# A room change or the viewer's answer can take minutes.\ntool_timeout_sec = 300\n" + TOML_END + "\n"


## Codex's config.toml with the app's block up to date at its end and the user's lines kept above it. A table of the
## user's own under our name wins: then the app's block goes.
static func merged_codex_config(existing: String, id: String) -> String:
	var rest := existing
	var from := rest.find(TOML_BEGIN)
	var to := rest.find(TOML_END)
	if from >= 0 and to > from:
		rest = rest.left(from) + rest.substr(to + TOML_END.length()).trim_prefix("\n")
	if rest.contains("[mcp_servers.%s]" % MCP_NAME):
		return rest
	var mine := rest.strip_edges(false, true)
	return (mine + "\n\n" if mine != "" else "") + codex_block(id)


## The player's MCP server for the agent: the adapter and its helper copied into .player/mcp/, and the agent's own MCP
## config pointing at them. A config of the user's that isn't JSON is left alone.
static func _write_mcp(id: String) -> void:
	var dir := player_dir(id).path_join(MCP_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	for file in MCP_FILES:
		var text := FileAccess.get_file_as_string(MCP_SOURCE.path_join(file))
		var to := dir.path_join(file)
		if text != "" and (not FileAccess.file_exists(to) or FileAccess.get_file_as_string(to) != text):
			_write(to, text)
	var path := folder(id).path_join(str(AGENTS[id]["mcp_file"]))
	var had := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var wanted := ""
	if path.ends_with(".json"):
		var existing := {}
		if had.strip_edges() != "":
			var parsed: Variant = JSON.parse_string(had)
			if not (parsed is Dictionary):
				push_warning("Agents: %s is not JSON; left as it is" % path)
				return
			existing = parsed
		var merged := merged_mcp_json(existing, id)
		if merged == existing:
			return
		wanted = JSON.stringify(merged, "  ") + "\n"
	else:
		wanted = merged_codex_config(had, id)
	if wanted != had:
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		_write(path, wanted)


## Hands a link the agent wants opened to the player (as a browser, for a sign-in): one line in .player/open_url.
static func opener_text(id: String) -> String:
	return "#!/bin/sh\nprintf '%%s\\n' \"$1\" >>'%s/open_url'\n" % player_dir(id)


## Makes the working folder and what the terminal and the hooks need. "" or the reason.
static func prepare(id: String, install := false, plain := false, fresh := false) -> String:
	var a: Dictionary = AGENTS[id]
	var dir := player_dir(id)
	if DirAccess.make_dir_recursive_absolute(dir.path_join("bin")) != OK:
		return "could not make %s" % dir
	FileAccess.set_unix_permissions(dir, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
			| FileAccess.UNIX_EXECUTE_OWNER)
	var notes := folder(id).path_join(str(a["instructions"]))
	var had := FileAccess.get_file_as_string(notes) if FileAccess.file_exists(notes) else ""
	var wanted := merged_instructions(had, id)
	if wanted != had:
		_write(notes, wanted)
	_write(dir.path_join("hook.sh"), hook_text(), true)
	_write(dir.path_join("run.sh"), run_text(id, install, plain, fresh), true)
	_write(dir.path_join("bin/xdg-open"), opener_text(id), true)
	_write_mcp(id)
	var settings := folder(id).path_join(str(a["hooks_file"]))
	var existing := {}
	if FileAccess.file_exists(settings):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(settings))
		if not (parsed is Dictionary):
			# The user's own file and not one we can read: left alone (no context, no prompt detection).
			push_warning("Agents: %s is not JSON; left as it is" % settings)
			return ""
		existing = parsed
	var merged := merged_settings(existing, id)
	if merged != existing:
		DirAccess.make_dir_recursive_absolute(settings.get_base_dir())
		_write(settings, JSON.stringify(merged, "  ") + "\n")
	return ""


static func _write(path: String, text: String, executable := false) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Agents: could not write %s" % path)
		return
	f.store_string(text)
	f.close()
	if executable:
		FileAccess.set_unix_permissions(path, FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER
				| FileAccess.UNIX_EXECUTE_OWNER)


## The terminal to use: the first of TERMINALS on the system, or "".
static func terminal() -> String:
	if not terminal_override.is_empty():
		return terminal_override[0]
	for t in TERMINALS:
		for d in ["/usr/bin", "/usr/local/bin", "/bin"]:
			if FileAccess.file_exists(d.path_join(t)):
				return d.path_join(t)
	return ""


## The terminal's arguments for one agent: its class, its size, dark, large type, running run.sh.
static func terminal_args(id: String, terminal_path: String) -> Array[String]:
	var a: Dictionary = AGENTS[id]
	var run := player_dir(id).path_join("run.sh")
	match terminal_path.get_file():
		"konsole":
			return ["--separate", "--hide-menubar", "--hide-tabbar", "--name", str(a["class"]), "-p",
					"Font=Monospace,%d" % roundi(FONT_PX * 0.75), "-p", "TerminalColumns=%d" % COLUMNS, "-p",
					"TerminalRows=%d" % LINES, "-p", "ColorScheme=DarkPastels", "-e", "/bin/sh", run]
		"lxterminal":
			return ["--no-remote", "--class=%s" % a["class"], "--name=%s" % a["class"],
					"--title=%s" % a["name"], "--geometry=%dx%d" % [COLUMNS, LINES], "-e", "/bin/sh %s" % run]
	return ["-class", str(a["class"]), "-title", str(a["name"]), "-u8", "-fa", "monospace:pixelsize=%d" % FONT_PX,
			"-geometry", "%dx%d+0+0" % [COLUMNS, LINES], "-bg", BACKGROUND, "-fg", FOREGROUND, "-cr", FOREGROUND,
			"-sl", str(SCROLLBACK), "-tn", "xterm-256color", "+sb", "-b", "8",
			# No window border: on the Frame the capture's dmabuf import takes the buffer with the border (1922 x 1082)
			# against the window's 1920 x 1080 and the texture fails, a black pane.
			"-bw", "0", "-xrm", "*allowSendEvents: true", "-xrm", "*allowTitleOps: false", "-xrm", "*scrollKey: true",
			"-e", "/bin/sh", run]


## Closes the agent's terminal, which ends its session. By its class on the command line, as find_window() finds it.
static func stop(id: String) -> void:
	OS.execute("pkill", ["-f", str(AGENTS[id]["class"])])


## Starts the agent's terminal. "" or the reason. Its window comes a moment later (find_window()).
static func start(id: String, install := false, plain := false, fresh := false) -> String:
	var why := prepare(id, install, plain, fresh)
	if why != "":
		return why
	var t := terminal()
	if t == "":
		return "no terminal here (%s)" % ", ".join(TERMINALS)
	var args := terminal_args(id, t)
	if terminal_override.size() > 1:
		args = terminal_override.slice(1) + args
	# The Frame starts the app with no locale, or (Steam, 2026-11) with LC_ALL=C, which wins over LANG: xterm would read
	# the agent's UTF-8 as Latin-1 (-u8 doesn't win), every line, arrow and spinner mangled into what looks like
	# control codes, and the agent's tools would make a mess of file names. A UTF-8 locale, whatever was set.
	if not _utf8_locale():
		OS.set_environment("LC_ALL", "C.UTF-8")
	var cmd := [t, args]
	if terminal_override.is_empty():
		cmd = detached(t, args, id)
	var pid := OS.create_process(str(cmd[0]), PackedStringArray(cmd[1]))
	if pid < 0:
		return "could not start %s" % str(cmd[0]).get_file()
	print("Agents: started %s for %s (pid %d%s)" % [t.get_file(), id, pid,
			", outside the app's process tree" if cmd[0] != t else ""])
	return ""


## The environment the terminal is started with, outside the app's process tree: what a window and the agent need.
const DETACHED_ENV: Array[String] = ["DISPLAY", "XAUTHORITY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "PATH", "LANG",
		"LC_ALL", "LC_CTYPE"]


## The terminal's command, started outside the app's process tree when that is possible: as a transient unit of the
## user's service manager (systemd-run --user), so the terminal is not a child of the app. Steam's launch wrapper waits
## for every descendant of the app: a terminal left running kept it alive after the app had quit, and Steam refused
## the next launch as already running (2026-11-05). Returns [command, arguments]: systemd-run's, else the terminal's own.
static func detached(terminal_path: String, args: Array[String], id: String) -> Array:
	var run := "/usr/bin/systemd-run"
	if OS.get_name() != "Linux" or not FileAccess.file_exists(run) or OS.get_environment("XDG_RUNTIME_DIR") == "":
		return [terminal_path, args]
	var a: Dictionary = AGENTS[id]
	var out: Array[String] = ["--user", "--quiet", "--collect", "--unit=%s-%d" % [a["class"], Time.get_ticks_msec()],
			"--description=%s for the VR video player" % a["name"]]
	for v in DETACHED_ENV:
		if OS.get_environment(v) != "":
			out.append("--setenv=%s=%s" % [v, OS.get_environment(v)])
	out.append("--")
	out.append(terminal_path)
	out.append_array(args)
	return [run, out]


## Whether the locale that counts (LC_ALL, else LC_CTYPE, else LANG) names a UTF-8 character set.
static func _utf8_locale() -> bool:
	for v in ["LC_ALL", "LC_CTYPE", "LANG"]:
		var l := OS.get_environment(v)
		if l != "":
			return l.to_lower().replace("-", "").contains("utf8")
	return false


static func link_path(id: String) -> String:
	return folder(id).path_join(LINK_FILE)


## The curl config: the agent's way into the player's API. Never logged; not on any command line.
static func link_text(token: String, pin: String) -> String:
	return "# The VR video player's API, for an agent on this headset: curl -K %s %s/state\n" % [LINK_FILE, API_URL] \
			+ "# The guide: %s  Keep this file private.\n" % GUIDE_URL \
			+ "header = \"Authorization: Bearer %s\"\npinnedpubkey = \"%s\"\ninsecure\n" % [token, pin]


## Mode 600 before anything is in it.
static func write_link(id: String, token: String, pin: String) -> bool:
	DirAccess.make_dir_recursive_absolute(folder(id))
	var f := FileAccess.open(link_path(id), FileAccess.WRITE)
	if f == null:
		return false
	FileAccess.set_unix_permissions(link_path(id), FileAccess.UNIX_READ_OWNER | FileAccess.UNIX_WRITE_OWNER)
	f.store_string(link_text(token, pin))
	f.close()
	return true


## The token in the agent's link file, or "".
static func link_token(id: String) -> String:
	if not FileAccess.file_exists(link_path(id)):
		return ""
	for line in FileAccess.get_file_as_string(link_path(id)).split("\n"):
		if line.begins_with("header = "):
			return line.trim_prefix("header = \"Authorization: Bearer ").trim_suffix("\"")
	return ""


## The viewer forgot this client: its link file goes.
static func forget_link(client_name: String) -> void:
	for id: String in AGENTS:
		if AGENTS[id]["client"] == client_name and FileAccess.file_exists(link_path(id)):
			DirAccess.remove_absolute(link_path(id))


## The agent's terminal among an X11WindowSource's windows, by its class, or 0.
static func find_window(win: Object, id: String) -> int:
	var cls := str(AGENTS[id]["class"])
	for e: Dictionary in win.call("list_windows"):
		if cls in (str(e.get("class", "")) + " " + str(e.get("instance", ""))).to_lower():
			return int(e.get("id", 0))
	return 0
