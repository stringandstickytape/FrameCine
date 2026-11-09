PC windows @VERSION@, for FrameCine on the Steam Frame

pc-windows.exe sends the windows and monitors of this PC to the headset, with the PC's sound. In the headset each
window is a pane that you can move and resize, or put on the big screen. A mouse and keyboard paired with the headset
control the window. MIT licence (LICENSES/).

Needs: Windows 10 2004 or later, 64-bit, a GPU with a hardware video encoder (HEVC or H.264), and the PC and the
headset on the same home network. Nothing to install: this is one program.

First run
  1. Unzip this folder anywhere (for example Documents) and start pc-windows.exe.
     Windows can show "Windows protected your PC" (the program is not signed): More info, Run anyway.
     If Windows asks whether it may use the network, allow private networks.
  2. A tray icon appears, and the window opens by itself until a headset is paired.
  3. In the headset: Menu, System, PC windows: turn it on, then Add a PC. It shows six digits for 10 minutes.
  4. Type the six digits into Pairing code in the PC window and press Pair.
  From then on the two connect by themselves whenever both are on. The window can stay closed.
  In the headset: Files, PC windows: pick a window or a monitor.

The tray icon
  Click it to show or hide the window: the headset, what is sent, the video encoder, Forget headset and Quit.
  Right-click it for Show and Quit. Closing the window keeps the program running in the tray; Quit stops it.
  To start it when you sign in: Win+R, shell:startup, and put a shortcut to pc-windows.exe in that folder.

Taking the PC back
  The PC's own mouse and keyboard always win: the headset's input waits until they have been still for 4 seconds.
  Ctrl+Alt+F12        hands off: the headset's mouse and keys are ignored until you press it again
  Ctrl+Alt+Shift+F12  also stops sending: every window and the sound stop until you press it again

Privacy
  It sends only to the paired headset, over TLS, on the home network (private addresses only). Nothing listens on
  the PC: it connects to the headset. Window titles, pictures and sound are not kept or logged.
  The pairing is kept in %APPDATA%\pc-windows\pairing.dat, encrypted for your Windows user. The log
  (%APPDATA%\pc-windows\pc-windows.log) has sizes, rates and errors only.

Stop or uninstall
  Quit it from the tray icon. To uninstall: press Forget headset first (optional), Quit, delete this folder,
  delete %APPDATA%\pc-windows, and delete the shortcut in shell:startup if you made one.
  In the headset, System, PC windows: Forget removes this PC there.

More: https://github.com/stringandstickytape/FrameCine/blob/main/docs/install.md
