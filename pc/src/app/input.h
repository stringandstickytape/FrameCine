// The headset's mouse and keys, replayed on the PC with SendInput, and bringing a window to the front.
#pragma once

#include <string>

#include "window_list.h"

namespace pcw::input {

enum class MouseEvent { Move, Down, Up, Wheel };

// (x, y) in the stream's pixels (stream_w x stream_h); the cursor goes to that point of the window as it is now.
void mouse(const Target& t, MouseEvent ev, double x, double y, int stream_w, int stream_h, const std::string& button,
           double dx, double dy);
// A key by Godot's name; false when the name is not known.
bool key(const std::string& godot_name, bool down);
// Text typed as it is (each character as a Unicode key press; new lines and tabs as Enter and Tab).
void text(const std::string& utf8);
// Brings the window to the front (restoring it when minimised). Windows lets a background process do that only
// in some cases, so a few ways are tried. True when it is in front after.
bool focus(const Target& t);
// Lets go of every key and button still held down (when the headset goes, so nothing stays stuck).
void release_all();

// Who has the PC's mouse and keyboard (the user, 2026-11-08: a way out when the headset's mouse is on the PC). The
// PC's own mouse and keyboard always win: once either is used, the headset's input is ignored until it has been
// still for a few seconds. Hands off (Ctrl+Alt+F12) ignores the headset's input until switched back.
void set_hands_off(bool on);
bool hands_off();
// Watches the PC's own mouse and keyboard with low-level hooks (Windows marks injected input, ours, so the two are
// told apart). Call on a thread with a message loop (the window's).
void watch_local_input(bool on);
// True once each time the PC's own input takes over after a quiet spell (to tell the headset).
bool take_local_takeover();
// Off: the PC's own input never holds back the headset's (tests, run while someone types at the PC).
void set_local_yield(bool on);

// The cursor's shape now, in the protocol's words (arrow, ibeam, hand, ...).
std::string cursor_shape();

}  // namespace pcw::input
