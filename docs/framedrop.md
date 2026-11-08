# Release through FrameDrop, with our own updates

Research notes 2026-11-05, plan 2026-11-08 (`docs/decisions.md` D32). Not yet tested on the device.

The plan in short:

1. **First install through FrameDrop.** A user clicks "Install with FrameDrop" on the README. FrameDrop copies a zip
   to the headset and adds it to Steam. No ssh, no terminal.
2. **The first launch installs the player into the home folder** (`~/vr-video-player`), outside the Steam Linux
   Runtime container, and adds the normal Steam library entry. From then on the player runs as it does now.
3. **The player updates itself** from GitHub Releases. FrameDrop is not necessary again.
4. **The speech model is not in the package.** The player downloads it once, the first time voice is used, into
   its data folder. The package is about 264 MB smaller, and updates do not carry the model.

## What the user does

The FrameDrop steps are from its site; the steps marked "not seen" are not confirmed.

Once, on the PC (Windows only; a Linux FrameDrop is planned, a Mac one "possibly"):

1. Download `FrameDrop-Setup-<version>.exe` from <https://framedropvr.com/> and run it. FrameDrop needs the
   Microsoft Edge WebView2 Runtime (Windows 11 has it; the site tells Windows 10 users how to get it). Not seen:
   whether SmartScreen shows an "unknown publisher" warning.
2. Start FrameDrop once. This registers `framedrop://`, so that the install link can open it.

Once, on the headset:

3. Steam Settings > System: turn on Developer Mode.
4. Settings > Developer > Pair new host, then Pair in FrameDrop. The PC and the headset must be on the same
   network.

The install:

5. Start Steam on the headset.
6. On the README, click "Install with FrameDrop". FrameDrop opens and asks for a confirmation.
7. FrameDrop downloads the zip from our release (well under 100 MB without the model), copies it to the headset
   and adds "VR Video Player (installer)" to the Steam library.
8. On the headset, start "VR Video Player (installer)". It installs the player into the home folder and adds
   "VR Video Player" to the library (some seconds), then tells the user to restart Steam.
9. Restart Steam (or the headset). Not known: whether the installer can restart Steam itself.
10. Start "VR Video Player". After this: updates come in the player ("Restart now to update?"), and voice
    downloads its model when it is first used.

About five steps once, then six to install. The rough parts:

- **The Steam restart (step 9).** If a Devkit Game can run without the container, steps 8 and 9 are not
  necessary (see "To find out on the device"). This is the first thing to test.
- **Two library entries.** The manifest's `name` is "VR Video Player (installer)", so that the two entries are
  different. The installer can offer to remove its own entry after the install, if a Devkit Game entry can be
  removed from the headset (not known; it is not in `shortcuts.vdf`).
- **The order on the README.** If FrameDrop is not installed, the link only opens the FrameDrop site, and the user
  must come back and click it again. The README gives steps 1 to 4 above the button.
- **No Windows PC, or no Developer Mode:** the README gives the ssh install (`tools/install-on-frame.sh`) as a
  second method, step by step.

## What FrameDrop is

FrameDrop is a free Windows program from an independent XR developer (CadeXR) that sideloads software onto the
Steam Frame from a PC. Valve did not make it, and Valve has published no statement about it. Website:
<https://framedropvr.com/>. The version seen was 1.0.37, on 2026-11-05 and again on 2026-11-08 (Windows installer
only; the site gives no release date and has no changelog). The licence is "DonationWare": free to use, donations
optional. The site gives no terms for developers and has no catalogue or developer listing.

It accepts three types of payload:

| Payload | Runtime on the headset | Notes |
|---|---|---|
| Android APK | Lepton (Android 11, API 30) | Must be `arm64-v8a` or a universal APK that includes it. VR (OpenXR) and flat modes. |
| Linux build (zip or folder) | Steam Linux Runtime 4.0 ARM64 | ARM64 runs natively; x86_64 maps to SLR 4.0 and needs translation. |
| Windows `.exe` | Proton | ARM64 Proton must already be installed on the headset. |

## How it works

- It uses Valve's SteamOS Devkit path and the same tools as the SteamOS Devkit Client: it pairs through the Devkit
  service, then copies with SSH and rsync.
- The headset must be in Developer Mode (Steam Settings > System). Pairing is done once: on the headset,
  Settings > Developer > Pair new host, then Pair in FrameDrop. Steam must be open on the headset during an install.
- When the user drops a file, FrameDrop finds the runtime that the title needs, writes the start command and
  launch arguments, and registers the title as a Devkit Game in Steam. The user starts it from the Steam library.
- Zips are unpacked **on the PC** before the copy. One wrapper folder in the zip is permitted. The site does not
  mention `.tar.gz`.
- The PC and the headset must be on the same network. The headset's IP address can be typed in if its name does not
  resolve.

The site does not say:

- how FrameDrop selects the launch file when the folder has more than one executable, and there is no manifest field
  to set it;
- whether a Linux build can run outside the runtime container;
- where Devkit Games are put on the headset, what a second install of the same title does, or how to uninstall;
- whether the execute bit survives the unzip on Windows;
- a size limit.

## The install button for developers

A developer can put an "Install with FrameDrop" link on a web page. The link opens FrameDrop on the visitor's PC
(Windows registers `framedrop://` the first time FrameDrop runs). If FrameDrop is not installed, the link goes to the
FrameDrop site. FrameDrop asks the user to confirm before it installs. The visitor must have paired a headset before.
The site recommends a normal download link next to the button.

- With a manifest: `https://framedropvr.com/install?manifest=<URL-encoded manifest URL>`
- With a file only: `https://framedropvr.com/install?url=<file URL>`

Manifest (these are all the fields that the site documents):

```json
{
  "schema": "framedrop.install/v1",
  "name": "VR Video Player (installer)",
  "files": [ { "url": "https://github.com/stringandstickytape/steam-frame-vr-video-player/releases/download/<tag>/vr-video-player-<version>-arm64.zip",
               "sha256": "<sha256 of the zip>" } ]
}
```

- `name` is the title that shows in Steam. `sha256` is optional, but the site recommends it.
- Any static host is permitted, for example GitHub Releases.
- HTTPS is necessary (HTTP only from `localhost`, for tests). The URL must end in a file name. `file://` URLs, LAN
  addresses and credentials in the URL are not permitted.

## Frame Control, a second installer with the same links

Frame Control (<https://github.com/saphid/frame-control>, MIT, read 2026-11-09) is an open-source PC app for the Frame
(Windows, macOS, Linux, iPhone). It reads FrameDrop's manifest (`framedrop.install/v1`), so one manifest serves
both. Its link is `frame-control://install?manifest=<URL-encoded manifest URL>` (`docs/web-install.md` there). Its
extension `files[0].exe` names the program in a zip to run (for us `run.sh`), and `files[0].size` the size.

- It installs a zip the same way as Valve's Devkit Client: `~/devkit-game/<id>/`, then `create-shortcut`. An ARM64
  Linux build gets `compat_tool` `SteamLinuxRuntime_4-arm64`, like FrameDrop, and a link cannot choose another. So
  the first launch is in the container with either tool.
- Its rules: HTTPS only, public hosts only, at most 4 GiB, the sha256 checked, and the user confirms.
- One report (not checked) says FrameDrop cannot download from GitHub at present. If so, Frame Control is the
  first link on the README until FrameDrop is fixed.

**In practice there is no container (2026-11-09).** A probe registered over ssh with `compat_tool`
`SteamLinuxRuntime_4-arm64` (as both tools do) started natively both times: parent `reaper`, no
`_v2-entry-point` in Steam's launch line. Frame Control's own headset test found the same ("Steam records the
mapping (`CompatToolMapping`) but launches the devkit title without the runtime's `_v2-entry-point` prefix",
`docs/sideloading.md` there). So the player runs where the tool put it, `~/devkit-game/<id>/`, and needs no
first-launch install step. Should Steam start to apply the runtime one day, `run.sh` can turn its own entry into a
native one: the home folder is shared, so it can write `compat_tool: ""` into `~/devkit-game/<id>-settings.json`
(the id is its own folder's name) and send `create-shortcut` for the same id through `~/.steam/steam.pipe`. That
path is written but untested, because the container never ran.

## The problem: the runtime container

FrameDrop runs ARM64 Linux builds in Steam Linux Runtime 4.0 (Debian 13). This is almost certainly a
pressure-vessel container with its own `/usr`. The home folder, `/dev`, `/sys` and the network are usually shared
with the container. The host's programs are not on the usual paths (they are under `/run/host/usr`, with the host's
libraries, which the container does not load).

The player runs outside a container at present (`DISPLAY=:0`, the X11 display driver, the host libraries), and parts
of it start host programs:

| Feature | Host programs | File |
|---|---|---|
| Android apps | `/usr/bin/kwin_wayland`, `systemd-run --user`, `systemctl --user` | `app/scripts/android/lepton.gd` |
| Agent terminal | `/usr/bin/systemd-run`, xterm or konsole, `claude` or `codex` | `app/scripts/agents/agent_terminal.gd` |
| Other | `pactl`, `sqlite3`, `node`, `python3` (if the runtime does not have them) | several |

Also not known in the container: the hardware decoder (`/dev/video-dec0`, question 6 in `docs/research-device.md`),
OpenXR, passthrough and audio. The engine and `whisper-server` need glibc 2.38 or older, which Debian 13 has.

Thus the player must not run in the container. The FrameDrop package only installs it (next section).

## The first launch installs the player

The FrameDrop zip is the normal release package. Its `run.sh` does a check before it starts the engine:

1. **In the container?** (`/run/pressure-vessel` or `/.flatpak-info` exists, or `/usr` is not the host's.) If not,
   start the engine as usual. This keeps `run.sh` correct for every other install path.
2. **In the container:** copy the package to `~/vr-video-player.new`, then do the same steps as
   `tools/install-on-frame.sh` (start the new engine with `--version`, move the old install to
   `~/vr-video-player.old`, put the new one in its place, write the desktop entry).
3. Add the Steam library entry with `tools/steam_shortcuts.py --add --exe ~/vr-video-player/run.sh`.
4. Show the user what to do next. Steam reads `shortcuts.vdf` only when it starts, so Steam must restart once. If the
   container can show a window, a short message; else a line in the log and a notification. The best case: Steam
   restarts by itself (find out if the Devkit service or `steam://` can do this).

After this, the user starts "VR Video Player" from the library entry, which runs outside the container. The
FrameDrop entry ("VR Video Player (installer)") can stay (it installs again, which is harmless) or be removed.

Checked on the device 2026-11-09, without FrameDrop: the headset already has `SteamLinuxRuntime_4-arm64` (steamrt4
4.0.20261021, pressure-vessel 0.20261007), and its `run -- <command>` starts a command in the same container.

- `python3` is there (3.13, with `zipfile`, `hashlib` and `ssl`), so `steam_shortcuts.py` runs as it is. Also
  `bash`, `curl` and `xterm`; not `rsync`, `pactl`, `sqlite3`, `node`, `systemd-run`, `systemctl` or `kwin_wayland`.
- The home folder is writable, and so is `shortcuts.vdf`.
- `/dev/video-dec0` opens; `/dev/dri` is there. The host's programs are under `/run/host/usr/bin`. glibc is 2.43.
- The OpenXR runtime file in `~/.config/openxr/1/` is visible (OpenXR itself not tried: the player runs outside).

FrameDrop is closed source (no licence or repository on its site), but it uses Valve's SteamOS Devkit path, and
Valve's Devkit Client is MIT (<https://gitlab.steamos.cloud/devkit/steamos-devkit>, read 2026-11-09):

- The client copies with rsync `--chmod=Du=rwx,Dgo=rx,Fu=rwx,Fog=rx`: every file arrives executable.
- The files go to `~/devkit-game/<gameid>/`. The command line, environment and settings go to
  `~/devkit-game/<gameid>-argv.json`, `-env.json` and `-settings.json`.
- `devkit-utils/steam-client-create-shortcut` registers the title with Steam at once, through `~/.steam/steam.pipe`
  (`devkit-1 steam://devkit-1/<token from ~/.steam/steam.token>/create-shortcut?...`). No Steam restart.
- The runtime is the setting `compat_tool`: `SteamLinuxRuntime_4-arm64`, `lepton`, `proton-stable` and others, or
  empty ("Not specified"). `steamos-delete` removes a title.

Tested on the device 2026-11-09 with a probe title (a script that records where it runs), registered over ssh
with Valve's `steam-client-create-shortcut` and `"compat_tool": ""`:

- The game id must be letters and digits only. With a hyphen, Steam answers "missing/invalid arguments".
- The title appears at once in the library under **Non-Steam**. No Steam restart.
- Started from there, it runs **outside the container**: SteamOS, parent `reaper`, cwd its own folder,
  `DISPLAY=:1`, `XDG_RUNTIME_DIR=/run/user/1000`, Valve's Vulkan layers on, `systemd-run` there. That is the same
  start as the non-Steam shortcut the dev builds used.
- `steamos-delete --delete-title <id>` removes it from the library at once. (Valve's tools print Steam's session
  token in their debug output: never log that output.)

So whatever installs the player (the first launch from FrameDrop, or a PC program) registers it as a Devkit Game
with no compat tool, and the user starts it from Non-Steam. No Steam restart, no `shortcuts.vdf` edit.

Still to find out with FrameDrop itself: which `compat_tool` and command line it writes (if it follows the Devkit
Client, the files are executable).

- Can a Devkit Game run without a compat tool (Steam > Properties > Compatibility)? If yes, the copy step is not
  necessary, but the updater (below) still needs an install folder that the player owns.
- Is the `--steam` library entry correct on the Frame? It is not yet tested (`docs/packaging.md`).

## Our own updates

Built 2026-11-08 (`app/scripts/update/`, `tools/player-run.sh`). Tested in WSL only; see "Not yet tested on the
device" below.

The player updates itself from GitHub Releases, wherever it is installed. FrameDrop has no update method, so this
is the only way that users get new versions without the install link again. It also replaces the update path for
installs made with `tools/install-on-frame.sh`.

### Folders

- **The install folder** is the folder that holds `run.sh`, wherever the PC tool put it: usually
  `~/devkit-game/<id>/`, or `~/vr-video-player/` after an ssh install. Nothing has it as a fixed path. The app
  finds it as the parent of its own `app/` folder, and it updates only when `run.sh` and `VERSION` are there. A run
  from the repository has neither, so it never checks.
- **The staging folder** is `${XDG_DATA_HOME:-~/.local/share}/vr-video-player/update/`, not in `~/devkit-game/`
  (Valve's tools treat each folder there as a title). It is on the same file system as the home folder, so a swap
  is a `mv`. It holds `package.part` and `package.part.json` (the download and the version it is for), `unpack/`
  while tar runs, `new/` (the staged version), `new.complete` (written last) and `old/` (the install before the
  last swap, one level).
- **The state folder** is `${XDG_STATE_HOME:-~/.local/state}/vr-video-player/`, with the logs. `run.sh` writes
  `swapped` and `bad-versions` there, and `update.log` (one line for each swap or rollback). The new version writes
  `started`.

Settings (`~/.local/share/godot/app_userdata/VR Video Player/`) and logs are outside the install folder, so an
update keeps them.

### The steps

1. **Check** (`updater.gd`, a feature: `main.features.update`). 8 s after the first frame, then once a day while
   the player runs. It gets `latest.json` and `latest.json.sig` from
   `https://github.com/stringandstickytape/steam-frame-vr-video-player/releases/latest/download/`. GitHub redirects
   this to the newest release that is not a draft or a pre-release. It is not the REST API, so the API's limit
   does not apply. `--update-url=URL` sets another base address, for tests. The format (shared with
   `tools/release.sh`):

   ```json
   { "version": "0.1.0", "tag": "v0.1.0",
     "package": { "url": "https://github.com/stringandstickytape/steam-frame-vr-video-player/releases/download/v0.1.0/vr-video-player-0.1.0-arm64.tar.gz",
                  "size": 61234567, "sha256": "<64 lowercase hex>" },
     "notes": "One line for the update prompt." }
   ```

   Versions are plain `MAJOR.MINOR.PATCH`. The installed version is the `version` line of `VERSION` (a leading `v`
   and a `git describe` tail are allowed). A package named by a commit has no release number, so it never updates.
2. **Verify the signature first.** `latest.json.sig` is the raw RSA PKCS#1 v1.5 signature over the SHA-256 of the
   exact bytes of `latest.json` (`openssl dgst -sha256 -sign key.pem`). The public key is
   `app/update/release-key.pub.pem`; without it, the check does not run. Without the signature, a person who gets
   access to the GitHub account could send code to each headset. The signature covers `package.sha256`, so it
   covers the package too. Then the version must be newer than the installed one and not in `bad-versions`.
3. **Download** the package to `package.part`, on the updater's thread. After a break it asks for the rest (an HTTP
   Range request). A `.part` for another version is deleted first. It stops after 30 s with no bytes and keeps what
   it has. Then the size and the SHA-256 must agree with `latest.json`; a wrong hash deletes the file.
4. **Stage.** The host's `tar` unpacks it into `unpack/` (the modes are kept). The package's one top folder
   (`vr-video-player-<version>-<arch>/`) becomes `new/`; a package without a top folder works too. Its `VERSION`
   must say the version of `latest.json`, and `bin/vr-video-player-engine --version` must start and print. Then
   `new.complete` (the version) is written, last. A `new/` without it is deleted.
5. **Ask.** "Restart now to update to 0.2.0?" with the release's one-line notes, in the menu's footer, with Restart
   and Later. Never during a film: the question shows when the menu opens with nothing open, or when the film ends
   (the end opens the menu). A paused film is still a film. Later means no more questions in this run. The System
   tab (Updates) shows the version, the download's progress and "Version 0.2.0 is ready. It goes in at the next
   start", with Restart now. The swap happens at the next start in any case, with no question.
6. **Restart.** On yes, the player writes what is open to `user://update_restart.cfg` (file, position, paused,
   room), saves the settings and the resume positions, and quits. A unit of the user's service manager
   (`systemd-run --user`, outside Steam's process tree, because Steam waits for every descendant of the title) waits
   for the player to end, then runs `steam steam://rungameid/$SteamGameId`. When Steam did not start the player
   (no `SteamGameId`), the question says "Quit now to update to 0.2.0? Then start the player again." The next start
   reads the file (only if it is less than 15 minutes old, and only if no `--file` was given), deletes it, opens the
   room and the file, and seeks to the position.
7. **Swap** (`run.sh`, before the engine starts; no network). If `new.complete` is there: the install folder moves to
   `old/`, `new/` moves into its place, `swapped` records the two versions, and the new `run.sh` runs. That first
   launch adds `launched` to `swapped`. Only forwards: a stage that is not newer than the install (it was installed
   again by hand since), or an install named by a commit, is deleted instead.
8. **Keep or roll back.** The new version writes `started` at its second frame. At the next launch, `run.sh` finds
   `swapped`: with `started`, the update is kept and both files go. Without it (the version was launched and showed no
   frame), it puts `old/` back into the install folder, deletes the failed version and adds its version to
   `bad-versions`, so the check skips it.

`run.sh` is made of functions that bash reads in full before the last line runs them. So moving its folder (and the
file) during the swap cannot change what bash reads next; after the move it runs the new `run.sh` with `exec`.
`tools/package.sh` copies `tools/player-run.sh` into the package as `run.sh`.

### Offline: never wait for the network

The player is often used with no network or a bad one. The updater must not delay or stop anything:

- **Nothing waits for the check.** Start-up, playback and the menus never wait for it. The check starts 8 s after
  the first frame, on a thread of its own (`HTTPClient`, polled, so the name lookup, the connection, TLS and each
  read have a limit). The hash, tar and the engine check run on the thread too. `run.sh` uses no network: the swap
  and the rollback are local file moves.
- **Short timeouts.** `latest.json` and its signature: 10 s in total, including the name lookup and the redirect.
  The package download: no total limit, but it stops if no bytes come for 30 s.
- **A failure is quiet.** No error on the screen; one log line. The next check is at the next start, or in a day.
  No fast retries.
- **A download that stops is kept.** The `.part` file continues at the next check (a Range request). If
  `latest.json` names a different version, the `.part` file is deleted first.
- **No half updates.** `new/` is used only when `new.complete` is there. A `new/` without it is deleted (by the
  player before it stages, and by `run.sh`).
- **The speech model too.** With no network, voice says that it needs a one-time download of 264 MB and the
  network, and the rest of the player works as usual. The same timeouts and continuation apply (not built yet).

Later, if the downloads are too large: publish the package in parts (engine, app, whisper), each with its hash, and
download only the parts that changed.

### Tests

- `app/tests/test_update.gd`: versions, `VERSION`, the checks of `latest.json`, the signature against a real openssl
  signature (another key, a changed byte, a cut signature, junk, no key), the bad-version list, the prompt rule,
  the question in the real menu (not over a playing or a paused film; with nothing open; Later), the restart state
  and its restore, the relauncher's command, the `started` marker, the System row.
- `app/tests/test_update_net.gd`: a local server (`app/tests/update_server.py`, with Range support) and a test film
  that plays the whole time. No network (a closed port), an address that does not answer, a name that does not
  resolve, a server that accepts and sends nothing (10 s), a wrong signature, a changed `latest.json`, a bad
  version, no newer version, a download cut at half and then continued from that byte, a stall, a `.part` of
  another version, a wrong hash, a redirect, a package without a top folder, an engine that does not start, a
  `new/` left half way. In each case the frames keep coming (no gap of 0.25 s), and the film plays at its speed.
- `tools/test_player_run.sh`: the swap, the next start that keeps it, a crash before the first frame (rolled back,
  recorded as bad), a `new/` without `new.complete`, a staged bad version, the `run.sh` file rewritten in place
  while its folder moves, a start with a relative `./run.sh`, a rollback with no `old/`, a stage older than the
  install, 0.10.0 after 0.9.0, an install named by a commit.
- Checked once by hand in WSL: the TLS connection to GitHub and the redirect to a real release asset work with the
  engine's own HTTPClient and the system's CA certificates (our repository has no release yet, so `latest.json` is a
  404, which is a quiet failure).

### Not yet tested on the device

- The whole path on the headset: the check over the headset's network, the CA certificates there, and the download
  speed.
- The restart through Steam: whether `steam steam://rungameid/$SteamGameId` from a `systemd-run --user` unit starts a
  Devkit Game again, whether `SteamGameId` holds the id that `rungameid` wants for a Devkit title, and the wait that
  Steam needs after the title ends (3 s now).
- The swap in `~/devkit-game/<id>/` while Steam knows the title: that the entry still starts the new folder.
- That the next start reopens the film where it was, in the headset.

## The speech model

### Permission

We can bundle whisper and its models, and we can host them ourselves:

- whisper.cpp (v1.9.5, our build): MIT.
- The speech models: OpenAI's Whisper weights, MIT. The ggml files come from the whisper.cpp project's Hugging Face
  repository (<https://huggingface.co/ggerganov/whisper.cpp>), also MIT.
- MIT only asks for the notice. `tools/package.sh` copies both into `LICENSES/`
  (`build/whisper/LICENSE-models.txt` has the OpenAI notice).
- Our build links libstdc++ and libgcc statically (the GCC runtime library exception permits this) and glibc
  dynamically. No GPL code is in it.

### Bundling is not necessary

`app/scripts/voice/whisper_backend.gd` already continues without it: one log line, and voice is not available.
`tools/package.sh --no-whisper` already makes a package without it.

### What the player does (built 2026-11-08)

The default model (`ggml-small.en-q8_0.bin`) is 264 MB (264477561 bytes, SHA-256
`67a179f608ea6114bd3fdb9060e762b588a3fb3bd00c4387971be4d177958067`), which is most of the package.
`whisper-server` (CPU build) is 4 MB and stays in the package.

- **Where the model is looked for** (`app/scripts/voice/whisper_backend.gd`): `whisper/models/` next to the server
  first, as before (a package made with `--whisper-model`, the benchmark kit, an old package), then
  `user://whisper-models/`. A file there of the wrong size is deleted and downloaded again.
- **When it downloads:** the first time voice is used (push-to-talk in the assistant, the browser, an agent pane or
  a PC window) with the server there and no model. Nothing happens at start-up: the backend only notes that the
  model is missing. Only the default model downloads; another `[voice] whisper_model` that is missing stays off,
  with the log line as before.
- **No confirmation.** Pressing the talk button is the request, as the app does its own setup elsewhere (no step for
  the user). Before any byte comes, the notice says what it is and how big: "Voice needs a one-time download of
  about 264 MB. Downloaded: 0 %. The rest of the player works as usual." It comes 1.2 s after the button is let
  go, so it does not hide "Listening". The assistant's card line for the clip says the same.
- **Progress:** a notice at 25, 50 and 75 %, the same line again at each use of voice while it downloads, and "Voice
  is ready." when the server answers with the new model. Notices go through `ui_layer.notify()`: the panel's footer
  when it is open, else the quiet line in the world. The assistant's status (`describe()`) shows the percentage.
- **From where:** `https://github.com/stringandstickytape/steam-frame-vr-video-player/releases/download/models-1/ggml-small.en-q8_0.bin`.
  The address, the size and the SHA-256 are constants in `app/scripts/voice/model_download.gd` (`RELEASES`,
  `MODEL_RELEASE`, `MODEL_FILE`, `MODEL_SIZE`, `MODEL_SHA256`); the rename to FrameVRVideo changes `RELEASES` only.
  `--model-url=URL` takes it from elsewhere (tests, a mirror).
- **How** (`model_download.gd`, one worker thread; the main thread only reads the progress): the bytes go to
  `ggml-small.en-q8_0.bin.part`; a part from an earlier try continues with `Range: bytes=N-` (206 appends; a 200
  starts over; 416 means the part is complete). Up to 5 redirects (GitHub sends the download to its asset host).
  Timeouts: 15 s for the name lookup, the connection and TLS together, then it stops when no bytes come for 30 s; no
  total limit. When the part is complete, its size and SHA-256 are checked, and only then is it renamed into
  place; a wrong hash deletes the part. 200 MB must stay free on the disk. HTTPS is used without the certificate
  check: the SHA-256 in the app is the trust, the file is public, and a headset without the engine's CA list can
  still download it.
- **Offline:** a failure is one log line and one notice. No network, no answer or a cut connection: "Voice needs
  the network once, for a download of about 264 MB. The rest of the player works as usual." Anything else (HTTP
  404, a wrong hash, a full disk): "The speech model did not download. Voice tries again when you use it next." The
  next use of voice tries again, but not sooner than 60 s after the failure (`RETRY_SECONDS`); uses before that
  repeat the line at most every 6 s. There are no retries of its own. Start-up, playback and the menus never wait
  for it.
- **When the assistant goes off mid-download** (the backend node leaves the tree), the download stops at once and
  the part stays for the next try.
- **The release:** `tools/upload-model.sh` makes the `models-1` release with the model, `SHA256SUMS` and the
  model's MIT notice. It reads the repository, tag, name, size and hash from `model_download.gd` and checks the file
  against them. The release is a pre-release and `--latest=false`, so `releases/latest`, which the updater reads,
  never returns it; the script checks that after publishing. Dry run by default; `--publish` does it. Not yet
  published.
- **Tests:** `app/tests/test_model_download.gd` with `app/tests/model_server.py` (a local server with range
  requests and faults): the lookup order, the size and hash check, a redirect, a download cut at half and
  continued, a server that ignores the range, a wrong hash, HTTP 404, no listener, a name that does not resolve, an
  address with no route, a server that accepts and sends nothing, one that stops in the body; frames go on in each.
  Then the backend: it waits, downloads at the first use, one offline notice, no new try before 60 s, the notice's
  text, the node leaving mid-download, and (with `WHISPER_TEST_DIR` and `WHISPER_TEST_MODEL`) the real server
  started on a downloaded model.

The model is outside the install folder, so updates do not download it again.

**Not yet tested on the headset:** the download over the headset's network from GitHub (the redirect to the asset
host, TLS with the engine, the speed), the notices in the world and on the card while a film plays, playback
smoothness while it downloads and while the hash is computed (about 1 s of one core), the disk space check on the
headset's file system, and the whole first-use flow after `user://whisper-models/` is removed (test plan step 7).
The release itself does not exist yet: until `tools/upload-model.sh --publish` runs, the download fails with HTTP
404 ("did not download").

## Changes to make

1. `tools/package.sh`: a `--zip` output. Write it with Python `zipfile` and set the Unix mode of each entry in
   `external_attr`, with the same rules as the tarball (folders, the engine, `*.sh` and the whisper programs 755;
   other files 644). FrameDrop unzips on Windows, so the execute bit can be lost; the test finds out.
2. `tools/package.sh`: no model by default (above); `SHA256SUMS`, `latest.json` and `latest.json.sig` for the
   release. The signing step runs on the PC that has the private key, not on GitHub.
3. `run.sh`: the container check and the first-launch install; the swap and the rollback for updates (done
   2026-11-08, `tools/player-run.sh`).
4. The player: the update check, download, verify and stage, and the setting to stop the check (done 2026-11-08,
   `app/scripts/update/`); the model download.
5. The release: the zip, the tarball, `SHA256SUMS`, `latest.json`, `latest.json.sig`, the manifest. The README:
   the user's steps (above), the FrameDrop link, the ssh install as a second method, and a normal download link.
6. Before each publish: no personal data in the package (library titles, user paths, LAN addresses, logs).

The launch file name must have no space (FrameDrop's troubleshooting: Steam cannot find it). `run.sh` has none.

## Test plan

1. Add `--zip` to `tools/package.sh` and make a zip.
2. On the PC: install FrameDrop, pair the headset, drop the zip (the developer side only).
3. On the headset (over ssh): read the Devkit Game entry (the start command and the runtime that FrameDrop
   selected). Find out where the files are, if they are executable, and which file FrameDrop starts.
4. In the container, from a launch through Steam: is `python3` there, is the home folder writable, does
   `/dev/video-dec0` open, does OpenXR start? Record the answers here and in question 6 of
   `docs/research-device.md`.
5. The first-launch install: the library entry, the Steam restart, then play an HEVC file and an AV1 file from the
   library entry. Confirm hardware decode, XR, passthrough, audio and the assistant link.
6. Updates: install an older package, serve a test `latest.json` and package (`--update-url`, a test repository
   or a local server), and let the player update itself. Then a bad release (an engine that does not start) to
   test the rollback, a bad signature, a wrong hash, and the offline tests ("Offline: never wait for the
   network").
7. The model: remove `user://whisper-models/`, use voice, and confirm the download and the transcription.
8. Result:
   - If it all works: publish the zip and the manifest with each release, and add the link to the README.
   - If the first-launch install cannot work in the container: do not use FrameDrop.
     `tools/install-on-frame.sh` stays the first install, and the updater is still useful. Record the result in
     `docs/decisions.md` (D32).

## Sources

- FrameDrop, About (Devkit path, runtimes, troubleshooting): <https://framedropvr.com/about>
- FrameDrop, Docs (manifest, hosting, install link): <https://framedropvr.com/docs>
- FrameDrop, How to use (pairing, zips, Steam shortcut): <https://framedropvr.com/how-to>
- PC Guide, FrameDrop launch: <https://www.pcguide.com/news/steam-frame-sideloader-is-already-available-as-xr-developer-launches-easy-to-pair-and-use-framedrop/>
- Steam Deck HQ, FrameDrop announced: <https://steamdeckhq.com/framedrop-sideloader-announced/>
- GitHub, linking to the latest release's assets (`/releases/latest/download/<file>`):
  <https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases>
- This repository: `tools/package.sh`, `tools/install-on-frame.sh`, `docs/packaging.md`, `docs/research-device.md`
  (section 4 and question 6), `build/whisper/README.md`, `app/scripts/voice/whisper_backend.gd`
