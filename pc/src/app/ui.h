// The tray icon and the small window: the headset found, connected and paired; the field for the pairing code;
// what is being sent; Forget and Quit.
#pragma once

#include <windows.h>

#include "control.h"

namespace pcw::ui {

// Runs the message loop until Quit. `show` opens the window at once (it does when not paired yet).
int run(HINSTANCE inst, Session& session, bool show);

}  // namespace pcw::ui
