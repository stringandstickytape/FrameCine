# Install FrameCine

Draft, 2026-11-09, for release 0.1.0. The README does not link here yet. The steps with Frame Control and FrameDrop
follow those tools' own documentation and our tests of the same install path over ssh; a full install through each
tool on the headset is still to be done.

FrameCine runs on the Steam Frame. It is free, and all of it is on GitHub. Install it from a PC once; after
that it updates itself.

- [With Frame Control or FrameDrop](#with-frame-control-or-framedrop) (the usual way)
- [Over ssh](#over-ssh) (a second way, for people who already use ssh with the headset)
- [Updates](#updates)
- [Uninstall](#uninstall)
- [PC windows: your PC's windows in the headset](#pc-windows-your-pcs-windows-in-the-headset) (optional)

All downloads are on the [releases page](https://github.com/stringandstickytape/FrameCine/releases).

## With Frame Control or FrameDrop

Frame Control and FrameDrop are free PC programs from other developers that put programs on the Steam Frame. Use
one of them:

- **Frame Control**: Windows, macOS or Linux. Open source. <https://github.com/saphid/frame-control>
- **FrameDrop**: Windows. <https://framedropvr.com/>

Once:

1. **On the headset:** open Steam Settings > System and turn on **Developer Mode**.
2. **On the PC:** install Frame Control or FrameDrop and start it once.
3. **Pair the headset with the PC.** On the headset: Settings > Developer > **Pair new host**. Then press **Pair**
   in the PC program. The PC and the headset must be on the same network.

The install:

4. Start Steam on the headset (it must be open during the install).
5. Do one of these:
   - Click the install link for your program (the PC program asks you to confirm):
     - Frame Control:
       `frame-control://install?manifest=https%3A%2F%2Fgithub.com%2Fstringandstickytape%2FFrameCine%2Freleases%2Flatest%2Fdownload%2Finstall-manifest.json`
     - FrameDrop:
       <https://framedropvr.com/install?manifest=https%3A%2F%2Fgithub.com%2Fstringandstickytape%2FFrameCine%2Freleases%2Flatest%2Fdownload%2Finstall-manifest.json>
   - Or download `framecine-<version>-arm64.zip` from the releases page and drag it onto the PC program.
     Do not unzip it first.
6. On the headset, open the Steam library. **FrameCine** is under **Non-Steam** (Steam shows Devkit titles by their id). Start it.

The PC program copies the player to the headset (about 100 MB) and adds it to the library. You do not need to restart
Steam. The player runs from the folder the program made for it (Frame Control: `~/devkit-game/FrameCine/`).

If the install link does nothing, the PC program is not installed or has not been started once. Start it, then
click the link again. If the player is not in the library, check that Steam was open on the headset during the
install, and install again.

## Over ssh

For people who can already reach the headset with `ssh` from a PC (Windows with Git Bash or WSL, Linux or macOS).
No root on the headset is necessary.

1. Make an entry `frame` in `~/.ssh/config` for the headset (or set `FRAME_HOST` to the ssh host name).
2. Get this repository (`git clone https://github.com/stringandstickytape/FrameCine`) and
   download `framecine-<version>-arm64.tar.gz` from the releases page.
3. Run:

   ```
   tools/install-on-frame.sh framecine-<version>-arm64.tar.gz --steam
   ```

   This copies the player to `~/framecine` on the headset, checks that it starts, and keeps the previous
   install as `~/framecine.old`. `--steam` also adds the player to the Steam library (as a non-Steam game);
   restart Steam to see it. Without `--steam` it is only in the desktop session's menu.

To check a download first: put `SHA256SUMS` from the same release next to it and run `sha256sum -c SHA256SUMS
--ignore-missing`.

## Updates

The player updates itself from the releases page. You do not need the PC program again.

- Some seconds after it starts, and once a day while it runs, the player looks for a new release. This never delays
  start-up or playback. With no network it simply tries again later.
- When there is a new version, it downloads it in the background, checks its signature and checksum, and asks
  **Restart now to update?** It does not ask during a film.
- If the new version does not start, the player goes back to the previous version by itself.
- To turn the check off: Menu > System, the update setting. Only your IP address goes to GitHub with each check.
- Your settings, bookmarks and logs are kept through updates.

To update by hand instead, install the new release the same way as the first time.

## Uninstall

- **Frame Control:** remove the title in Frame Control's list of titles. This removes the folder and the library
  entry.
- **FrameDrop:** how FrameDrop removes a title is not checked yet. By hand, in a terminal on the headset (or over
  ssh): delete the player's folder under `~/devkit-game/` and the `<folder name>-*.json` files beside it. Valve's
  devkit tool `steamos-delete --delete-title <folder name>` removes the library entry, where it is installed.
- **Over ssh:** `tools/install-on-frame.sh --uninstall --steam`.

Settings stay in `~/.local/share/godot/app_userdata/FrameCine/` and logs in `~/.local/state/framecine/`.
Delete these folders too to remove everything.

## PC windows: your PC's windows in the headset

PC windows is an optional small Windows program that sends windows and whole monitors from your PC to the headset,
with the PC's sound. Each window is a pane in front of you that you can move, resize, or put on the big screen. A
mouse and keyboard paired with the headset control the window; the controller's laser and trigger work as a mouse
too. You do not need it to watch films.

Needs: Windows 10 (2004 or later) or Windows 11, 64-bit; a GPU with a hardware video encoder (HEVC or H.264; most
current GPUs have one); the PC and the headset on the same home network.

### Download and first run

1. From the releases page, download `framecine-pc-<version>-windows-x64.zip` and unzip it anywhere (for
   example in Documents). There is nothing to install: it is one program, `pc-windows.exe`.
2. Start `pc-windows.exe`. Windows can show "Windows protected your PC", because the program is not signed: click
   **More info**, then **Run anyway**. If Windows asks whether it may use the network, allow **private networks**.
3. A tray icon appears (near the clock), and the program's window opens by itself until a headset is paired.

### Pair with the headset

1. In the headset: Menu > **System** > **PC windows**: turn it on, then press **Add a PC**. The panel shows six
   digits for 10 minutes.
2. On the PC: type the six digits into **Pairing code** and press **Pair**.

From then on the PC and the headset connect by themselves whenever both are on. In the headset, open **Files** >
**PC windows** and pick a window or a monitor. It opens as a pane in front of you.

- Squeeze and hold on a pane to move it; turn your hand to turn it. While you hold it, the stick makes it smaller
  or bigger (left, right) and moves it nearer or further (down, up).
- The pane you look at gets the keyboard and voice typing.
- **Show on the big screen** on the pane's bar puts the window where the film goes.

### The tray icon

- Click the tray icon to show or hide the window. It shows the headset, what is being sent, the video encoder in
  use, **Forget headset** and **Quit**. Right-click the icon for **Show** and **Quit**.
- Closing the window keeps the program running in the tray.
- To start it each time you sign in to Windows: press Win+R, type `shell:startup`, and put a shortcut to
  `pc-windows.exe` in the folder that opens.

### Taking the PC back

The PC's own mouse and keyboard always win. Move the PC's mouse or press a key, and the headset's mouse and keys are
ignored until the PC's have been still for about 4 seconds.

| Keys | What |
|---|---|
| Ctrl+Alt+F12 | Hands off: the headset's mouse and keys are ignored until you press it again |
| Ctrl+Alt+Shift+F12 | Also stops sending: every window and the sound stop until you press it again |

### Privacy

- It sends only to the paired headset, over an encrypted connection, on your home network. Nothing on the PC
  listens for connections: the program connects to the headset.
- It sends only what the headset asks for: the list of windows (titles and small thumbnails), the pictures of the
  windows you open, the sound while a pane is open, and the shape of the mouse pointer.
- Nothing is recorded. The pairing is kept in `%APPDATA%\pc-windows\pairing.dat`, encrypted for your Windows user.
  The log, `%APPDATA%\pc-windows\pc-windows.log`, has sizes, rates and errors, never titles, pictures, sound or
  what you type.

### Stop or uninstall

- To stop it: **Quit** in the window or in the tray icon's menu.
- To uninstall: press **Forget headset** (if you want the pairing gone first), **Quit**, then delete the folder you
  unzipped, the folder `%APPDATA%\pc-windows`, and the shortcut in `shell:startup` if you made one.
- In the headset: System > **PC windows** > **Forget** removes the PC there; turn **PC windows** off to stop the
  headset listening for PCs.
