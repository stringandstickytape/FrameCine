#!/bin/bash
# Spike 05 tests on the Steam Frame. Copy first (from the repository root on the PC):
#   ssh frame mkdir -p spike05
#   scp build/out/godot.linuxbsd.template_debug.arm64.PLAYER_WINDOW spikes/05-window/device-test.sh spikes/05-window/input-test.html frame:spike05/
#   scp -r spikes/05-window/project frame:spike05/
# Then:  ssh frame bash spike05/device-test.sh <test> [more main.gd arguments]
# Logs and screenshots go to ~/spike05/logs/<test>.log / .png.
#
# Tests:
#   inventory    read only, no window: gamescope's command line and root properties, X extensions, the xcb libraries,
#                Chromium's version, and the window list (headless, so gamescope's focus doesn't change).
#   capture      flat: capture the first Chromium window (zero copy if possible) for 1200 frames, screenshot 900 frames after the capture.
#   capture-shm  the same through the MIT-SHM copy path, for comparison.
#   input        launch Chromium on the input test page, send pointer/click/text/Enter/wheel as synthetic events,
#                screenshot 240 frames after the capture (the page lists what it received), then close that window.
#   input-xtest  the same through XTEST (raise the page's window, X focus to it, our window input-transparent).
#   focus        launch the test page (it may take gamescope's focus), capture it, and 150 frames later apply
#                FOCUS=<method[+method]> (default self-remap) to take focus back; prints gamescope's focus state before
#                and 60 frames after. Methods: self-remap, self-x, self-raise, self-gamescope (see main.gd).
#   xr           in the headset: the input test page on a screen in VR. Right controller = pointer (red dot on the
#                screen), trigger left click, squeeze right click, stick scroll, A Space, B browser Back. 3 minutes.
#   xr-chromium  the same with the user's own Chromium window (e.g. a video page) instead of the test page.
cd "$(dirname "$0")" || exit 1
BIN=./godot.linuxbsd.template_debug.arm64.PLAYER_WINDOW
export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000
mkdir -p logs
T=${1:?test name: inventory, capture, capture-shm, input, input-xtest, focus, xr, xr-chromium}
shift
FLAT="$BIN --path project --display-driver x11 --xr-mode off -- --no-xr"
PAGE="data:text/html;base64,$(base64 -w0 input-test.html)"

case "$T" in
inventory)
	{
		echo "== gamescope"
		pgrep -a gamescope
		echo "== root properties"
		xprop -root | grep -E '^(GAMESCOPE|STEAM|_NET_ACTIVE_WINDOW|_NET_SUPPORTING_WM_CHECK|_NET_CLIENT_LIST)'
		echo "== X server"
		xdpyinfo | grep -E '^(vendor string|vendor release|X.Org version)'
		xdpyinfo -queryExtensions | grep -E 'Composite|DAMAGE|XFIXES|XTEST|DRI3|MIT-SHM|Present'
		echo "== xcb libraries"
		ls -l /usr/lib/libxcb.so.1 /usr/lib/libxcb-composite.so.0 /usr/lib/libxcb-damage.so.0 /usr/lib/libxcb-xfixes.so.0 \
			/usr/lib/libxcb-xtest.so.0 /usr/lib/libxcb-dri3.so.0 /usr/lib/libxcb-shm.so.0
		echo "== chromium"
		flatpak info org.chromium.Chromium | grep -E 'Version|Commit|Runtime'
		pgrep -af chromium | head -3 | cut -c1-300
		echo "== windows (engine, headless)"
		$BIN --headless --path project --xr-mode off -- --list
	} 2>&1 | tee logs/inventory.log
	;;
capture)
	$FLAT --class=chromium --quit-after=1200 --screenshot="$PWD/logs/capture.png" --screenshot-frame=900 "$@" 2>&1 | tee logs/capture.log
	;;
capture-shm)
	$FLAT --class=chromium --shm --quit-after=1200 --screenshot="$PWD/logs/capture-shm.png" --screenshot-frame=900 "$@" 2>&1 | tee logs/capture-shm.log
	;;
input)
	$FLAT --launch="$PAGE" --title="x11window input test" --wait=40 --test-input=120 --quit-after=300 \
		--screenshot="$PWD/logs/input.png" --screenshot-frame=240 --close-on-exit "$@" 2>&1 | tee logs/input.log
	;;
input-xtest)
	$FLAT --launch="$PAGE" --title="x11window input test" --wait=40 --input=xtest --passthrough \
		--focus=target-raise+target-x@100 --test-input=120 --quit-after=300 \
		--screenshot="$PWD/logs/input-xtest.png" --screenshot-frame=240 --close-on-exit "$@" 2>&1 | tee logs/input-xtest.log
	;;
focus)
	# Launch the test page (a newly mapped window, which may take gamescope's focus), then try to take it back.
	$FLAT --launch="$PAGE" --title="x11window input test" --wait=40 --focus="${FOCUS:-self-remap}@150" --quit-after=330 \
		--close-on-exit "$@" 2>&1 | tee "logs/focus-${FOCUS:-self-remap}.log"
	;;
xr)
	# The input test page in the headset (it marks the pointer with a green dot and lists what it receives); 3 minutes.
	$BIN --path project --display-driver x11 --xr-mode on -- --launch="$PAGE" --title="x11window input test" --wait=40 \
		--quit-after=12960 --close-on-exit "$@" 2>&1 | tee logs/xr.log
	;;
xr-chromium)
	# The user's own Chromium window (e.g. a video page) in the headset; 3 minutes.
	$BIN --path project --display-driver x11 --xr-mode on -- --class=chromium --quit-after=12960 "$@" 2>&1 | tee logs/xr-chromium.log
	;;
*)
	echo "Unknown test $T"
	exit 2
	;;
esac
