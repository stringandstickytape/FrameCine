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

// The cursor's shape now, in the protocol's words (arrow, ibeam, hand, ...).
std::string cursor_shape();

}  // namespace pcw::input
