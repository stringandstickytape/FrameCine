// Godot's key names (OS.get_keycode_string of a physical keycode, core/os/keyboard.cpp) to what SendInput needs.
#pragma once

#include <cstdint>
#include <optional>
#include <string_view>

namespace pcw::keys {

struct KeyCode {
    // Set-1 scan code of the key's place on a US keyboard, 0 when the key is sent by virtual-key code only.
    // Physical keys go as scan codes so the PC's own keyboard layout decides the character, as a real
    // keyboard on the PC would.
    uint16_t scan = 0;
    bool extended = false;  // an E0 key: KEYEVENTF_EXTENDEDKEY
    uint16_t vk = 0;        // used when scan is 0 (media and browser keys, Pause, NumLock)
};

// Case-insensitive. Also takes the macOS and Windows spellings of the modifiers ("Command", "Option",
// "Windows"), and names that are only produced with Shift held ("Exclam"...) as the key that makes them.
std::optional<KeyCode> lookup(std::string_view godot_name);

// Every name Godot's table has, for the tests: whether each is mapped is checked there.
extern const char* const kGodotNames[];
extern const size_t kGodotNameCount;

}  // namespace pcw::keys
