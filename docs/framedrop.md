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

So the first launch could register the installed player as a Devkit Game itself, with no compat tool, and need no
Steam restart. To test on the device: does a title with an empty `compat_tool` run outside the container?

Still to find out with FrameDrop itself: which `compat_tool` and command line it writes (if it follows the Devkit
Client, the files are executable).

- Can a Devkit Game run without a compat tool (Steam > Properties > Compatibility)? If yes, the copy step is not
  necessary, but the updater (below) still needs an install folder that the player owns.
- Is the `--steam` library entry correct on the Frame? It is not yet tested (`docs/packaging.md`).

## Our own updates

When the player runs from `~/vr-video-player`, it can update itself. FrameDrop has no update method, so this is
also the only way that users get new versions without the button again. It also replaces the update path for
installs made with `tools/install-on-frame.sh`.

1. **Check.** At start, then once a day while the player runs, get
   `https://github.com/stringandstickytape/steam-frame-vr-video-player/releases/latest/download/latest.json`.
   This is a file download that GitHub redirects to the newest release that is not a draft or a pre-release. It
   is not the REST API, so the API's limit (60 requests an hour without a token) does not apply, and a change to the
   API's JSON cannot break the check. `latest.json` is small:

   ```json
   { "version": "1.4.0", "tag": "v1.4.0",
     "package": { "url": "https://github.com/.../releases/download/v1.4.0/vr-video-player-1.4.0-arm64.tar.gz",
                  "size": 61234567, "sha256": "<sha256>" },
     "notes": "One line for the update prompt." }
   ```

   Compare `version` with `VERSION` in the install folder. If the network or GitHub is not available, do nothing
   and try again at the next check (no error on the screen). Only the user's IP address goes to GitHub. A setting
   in System stops the check. A flag (`--update-url=URL`) sets another address, for tests.
2. **Download** the package from `package.url` to `~/vr-video-player.new.part`, with a progress bar. Continue after
   an interruption (HTTP range requests). Stop if the size is not `package.size`.
3. **Verify.**
   - `latest.json` has a signature (`latest.json.sig`, in the same release). The player has the public key and
     checks the signature with Godot's `Crypto` before it uses the file. Without this, a person who gets access to
     the GitHub account can send code to each headset. The private key stays off GitHub. One key for all releases;
     if the key changes, the release with the new key is signed with the old key too.
   - The SHA-256 of the package must agree with `package.sha256`. The signature covers this hash, so it covers the
     package too.
   - `SHA256SUMS` stays in each release, for people who download by hand.
4. **Stage.** Unpack to `~/vr-video-player.new`. Start the new engine with `--version`; stop if it does not start.
5. **Swap at the next start, not during a session.** The engine reads files from `app/` when it needs them, so the
   folder must not move while the player runs. `run.sh` does the swap before it starts the engine: move the current
   install to `~/vr-video-player.old` (one level), and `.new` to `~/vr-video-player`.
6. **Roll back if the new version fails.** The new version writes a "started" marker in
   `~/.local/state/vr-video-player/` when its first frame shows. If `run.sh` finds a swap without the marker at the
   next launch, it moves `.old` back and records the version as bad, so the check does not download it again.
7. **Restart.** The player asks "Restart now to update?". On yes, it writes the resume state (file, position, room)
   and restarts, as after a deploy. It does not ask during a film; it asks at the end, or at the next start.

Settings (`~/.local/share/godot/app_userdata/VR Video Player/`) and logs (`~/.local/state/vr-video-player/`) are
outside the install folder, so an update keeps them.

### Offline: never wait for the network

The player is often used with no network or a bad one. The updater must not delay or stop anything:

- **Nothing waits for the check.** Start-up, playback and the menus never wait for it. The check starts some
  seconds after the first frame, in the background (`HTTPRequest` with a thread; the name lookup does not block
  the main thread). `run.sh` uses no network: the swap and the rollback are local file moves.
- **Short timeouts.** `latest.json`: 10 s in total, including the name lookup and the redirect. The package
  download: no total limit, but it stops if no bytes come for 30 s.
- **A failure is quiet.** No error on the screen; one log line. The next check is at the next start, or in a day.
  No fast retries.
- **A download that stops is kept.** The `.part` file continues at the next check (range request). If
  `latest.json` names a different version, the `.part` file is deleted first.
- **No half updates.** `.new` is used only when it is complete and verified (a marker file written last). A
  `.new` without the marker is deleted.
- **The speech model too.** With no network, voice says that it needs a one-time download of 264 MB and the
  network, and the rest of the player works as usual. The same timeouts and continuation apply.
- **Tests:** no network, a name that does not resolve, a server that accepts the connection and sends nothing, a
  download cut at half. In each test the player starts and plays at its usual speed.

Later, if the downloads are too large: publish the package in parts (engine, app, whisper), each with its hash, and
download only the parts that changed.

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

### The plan

The default model (`ggml-small.en-q8_0.bin`) is 264 MB, which is most of the package. `whisper-server` (CPU build)
is 4 MB.

1. **Bundle `whisper-server`** in the package. It is small, and it agrees with the build.
2. **Download the model** the first time voice is used (or in the background after the first start), to
   `user://whisper-models/`. Show the size and the progress. No step for the user.
3. **Host it as a GitHub release asset** (one release for the models, which does not change), with its SHA-256 in
   the app. A change on Hugging Face cannot break the player then.
4. **`whisper_backend.gd` looks in `user://whisper-models/` too**, after the folders it uses now. A model in the
   package (from `--whisper-bench`, or an old package) still works.
5. **`tools/package.sh`** puts no model in the release package by default. `--whisper-model` puts one in, for
   offline installs and the benchmark kit.

The model is outside the install folder, so updates do not download it again.

## Changes to make

1. `tools/package.sh`: a `--zip` output. Write it with Python `zipfile` and set the Unix mode of each entry in
   `external_attr`, with the same rules as the tarball (folders, the engine, `*.sh` and the whisper programs 755;
   other files 644). FrameDrop unzips on Windows, so the execute bit can be lost; the test finds out.
2. `tools/package.sh`: no model by default (above); `SHA256SUMS`, `latest.json` and `latest.json.sig` for the
   release. The signing step runs on the PC that has the private key, not on GitHub.
3. `run.sh`: the container check and the first-launch install; the swap and the rollback for updates.
4. The player: the update check, download, verify and stage; the model download; the setting to stop the check.
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
