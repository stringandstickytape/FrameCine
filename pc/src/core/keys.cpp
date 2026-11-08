#include "keys.h"

#include <cctype>
#include <string>

namespace pcw::keys {

namespace {

struct Entry {
    const char* name;
    KeyCode code;
};

constexpr KeyCode S(uint16_t scan) { return {scan, false, 0}; }
constexpr KeyCode E(uint16_t scan) { return {scan, true, 0}; }
constexpr KeyCode V(uint16_t vk, bool extended = false) { return {0, extended, vk}; }

// Scan codes are set 1 (what Windows uses), for the key's place on a US keyboard; Godot's physical keycodes name
// places the same way. Virtual-key numbers are Windows' (winuser.h), written out so this file needs no Windows
// headers and the tests run anywhere.
const Entry kTable[] = {
    {"Escape", S(0x01)},
    {"Tab", S(0x0F)},
    {"Backtab", S(0x0F)},  // Shift+Tab on X11; Shift comes as its own key
    {"Backspace", S(0x0E)},
    {"Enter", S(0x1C)},
    {"Kp Enter", E(0x1C)},
    {"Insert", E(0x52)},
    {"Delete", E(0x53)},
    {"Pause", V(0x13)},   // its scan code is the E1 sequence, which SendInput cannot send
    {"Print", E(0x37)},
    {"SysReq", S(0x54)},
    {"Clear", V(0x0C)},
    {"Home", E(0x47)},
    {"End", E(0x4F)},
    {"Left", E(0x4B)},
    {"Up", E(0x48)},
    {"Right", E(0x4D)},
    {"Down", E(0x50)},
    {"PageUp", E(0x49)},
    {"PageDown", E(0x51)},
    {"Shift", S(0x2A)},
    {"Ctrl", S(0x1D)},
    {"Meta", E(0x5B)},
    {"Windows", E(0x5B)},
    {"Command", E(0x5B)},
    {"Alt", S(0x38)},
    {"Option", S(0x38)},
    {"CapsLock", S(0x3A)},
    {"NumLock", V(0x90, true)},
    {"ScrollLock", S(0x46)},
    {"F1", S(0x3B)},
    {"F2", S(0x3C)},
    {"F3", S(0x3D)},
    {"F4", S(0x3E)},
    {"F5", S(0x3F)},
    {"F6", S(0x40)},
    {"F7", S(0x41)},
    {"F8", S(0x42)},
    {"F9", S(0x43)},
    {"F10", S(0x44)},
    {"F11", S(0x57)},
    {"F12", S(0x58)},
    {"F13", S(0x64)},
    {"F14", S(0x65)},
    {"F15", S(0x66)},
    {"F16", S(0x67)},
    {"F17", S(0x68)},
    {"F18", S(0x69)},
    {"F19", S(0x6A)},
    {"F20", S(0x6B)},
    {"F21", S(0x6C)},
    {"F22", S(0x6D)},
    {"F23", S(0x6E)},
    {"F24", S(0x76)},
    {"Kp Multiply", S(0x37)},
    {"Kp Divide", E(0x35)},
    {"Kp Subtract", S(0x4A)},
    {"Kp Period", S(0x53)},
    {"Kp Add", S(0x4E)},
    {"Kp 0", S(0x52)},
    {"Kp 1", S(0x4F)},
    {"Kp 2", S(0x50)},
    {"Kp 3", S(0x51)},
    {"Kp 4", S(0x4B)},
    {"Kp 5", S(0x4C)},
    {"Kp 6", S(0x4D)},
    {"Kp 7", S(0x47)},
    {"Kp 8", S(0x48)},
    {"Kp 9", S(0x49)},
    {"Menu", E(0x5D)},
    {"Help", V(0x2F)},
    {"Back", V(0xA6, true)},
    {"Forward", V(0xA7, true)},
    {"Stop", V(0xA9, true)},
    {"Refresh", V(0xA8, true)},
    {"VolumeDown", V(0xAE, true)},
    {"VolumeMute", V(0xAD, true)},
    {"VolumeUp", V(0xAF, true)},
    {"MediaPlay", V(0xB3, true)},
    {"MediaStop", V(0xB2, true)},
    {"MediaPrevious", V(0xB1, true)},
    {"MediaNext", V(0xB0, true)},
    {"HomePage", V(0xAC, true)},
    {"Favorites", V(0xAB, true)},
    {"Search", V(0xAA, true)},
    {"StandBy", V(0x5F, true)},
    {"LaunchMail", V(0xB4, true)},
    {"LaunchMedia", V(0xB5, true)},
    {"Launch0", V(0xB6, true)},
    {"Launch1", V(0xB7, true)},
    {"JIS Eisu", V(0xF0)},
    {"JIS Kana", S(0x70)},
    {"Space", S(0x39)},
    // Names Godot gives keys that need Shift on a US keyboard; a physical keycode never is one, but a peer might
    // send them, and the unshifted key is the one place they can mean.
    {"Exclam", S(0x02)},
    {"QuoteDbl", S(0x28)},
    {"NumberSign", S(0x04)},
    {"Dollar", S(0x05)},
    {"Percent", S(0x06)},
    {"Ampersand", S(0x08)},
    {"Apostrophe", S(0x28)},
    {"ParenLeft", S(0x0A)},
    {"ParenRight", S(0x0B)},
    {"Asterisk", S(0x09)},
    {"Plus", S(0x0D)},
    {"Comma", S(0x33)},
    {"Minus", S(0x0C)},
    {"Period", S(0x34)},
    {"Slash", S(0x35)},
    {"0", S(0x0B)},
    {"1", S(0x02)},
    {"2", S(0x03)},
    {"3", S(0x04)},
    {"4", S(0x05)},
    {"5", S(0x06)},
    {"6", S(0x07)},
    {"7", S(0x08)},
    {"8", S(0x09)},
    {"9", S(0x0A)},
    {"Colon", S(0x27)},
    {"Semicolon", S(0x27)},
    {"Less", S(0x33)},
    {"Equal", S(0x0D)},
    {"Greater", S(0x34)},
    {"Question", S(0x35)},
    {"At", S(0x03)},
    {"A", S(0x1E)},
    {"B", S(0x30)},
    {"C", S(0x2E)},
    {"D", S(0x20)},
    {"E", S(0x12)},
    {"F", S(0x21)},
    {"G", S(0x22)},
    {"H", S(0x23)},
    {"I", S(0x17)},
    {"J", S(0x24)},
    {"K", S(0x25)},
    {"L", S(0x26)},
    {"M", S(0x32)},
    {"N", S(0x31)},
    {"O", S(0x18)},
    {"P", S(0x19)},
    {"Q", S(0x10)},
    {"R", S(0x13)},
    {"S", S(0x1F)},
    {"T", S(0x14)},
    {"U", S(0x16)},
    {"V", S(0x2F)},
    {"W", S(0x11)},
    {"X", S(0x2D)},
    {"Y", S(0x15)},
    {"Z", S(0x2C)},
    {"BracketLeft", S(0x1A)},
    {"BackSlash", S(0x2B)},
    {"BracketRight", S(0x1B)},
    {"AsciiCircum", S(0x07)},
    {"UnderScore", S(0x0C)},
    {"QuoteLeft", S(0x29)},
    {"BraceLeft", S(0x1A)},
    {"Bar", S(0x2B)},
    {"BraceRight", S(0x1B)},
    {"AsciiTilde", S(0x29)},
    {"Yen", S(0x7D)},
    {"Section", S(0x56)},  // the key beside left Shift on ISO keyboards (KEY_102ND); Godot calls it Section
};

bool same(std::string_view a, std::string_view b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        if (std::tolower(static_cast<unsigned char>(a[i])) != std::tolower(static_cast<unsigned char>(b[i]))) {
            return false;
        }
    }
    return true;
}

}  // namespace

std::optional<KeyCode> lookup(std::string_view name) {
    for (const Entry& e : kTable) {
        if (same(e.name, name)) return e.code;
    }
    return std::nullopt;
}

// Godot 4's table (core/os/keyboard.cpp), the Linux spellings of the modifiers.
const char* const kGodotNames[] = {
    "Escape", "Tab", "Backtab", "Backspace", "Enter", "Kp Enter", "Insert", "Delete", "Pause", "Print", "SysReq",
    "Clear", "Home", "End", "Left", "Up", "Right", "Down", "PageUp", "PageDown", "Shift", "Ctrl", "Meta", "Alt",
    "CapsLock", "NumLock", "ScrollLock", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12",
    "F13", "F14", "F15", "F16", "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24", "F25", "F26", "F27", "F28",
    "F29", "F30", "F31", "F32", "F33", "F34", "F35", "Kp Multiply", "Kp Divide", "Kp Subtract", "Kp Period",
    "Kp Add", "Kp 0", "Kp 1", "Kp 2", "Kp 3", "Kp 4", "Kp 5", "Kp 6", "Kp 7", "Kp 8", "Kp 9", "Menu", "Hyper",
    "Help", "Back", "Forward", "Stop", "Refresh", "VolumeDown", "VolumeMute", "VolumeUp", "MediaPlay", "MediaStop",
    "MediaPrevious", "MediaNext", "MediaRecord", "HomePage", "Favorites", "Search", "StandBy", "OpenURL",
    "LaunchMail", "LaunchMedia", "Launch0", "Launch1", "Launch2", "Launch3", "Launch4", "Launch5", "Launch6",
    "Launch7", "Launch8", "Launch9", "LaunchA", "LaunchB", "LaunchC", "LaunchD", "LaunchE", "LaunchF", "Globe",
    "On-screen keyboard", "JIS Eisu", "JIS Kana", "Unknown", "Space", "Exclam", "QuoteDbl", "NumberSign", "Dollar",
    "Percent", "Ampersand", "Apostrophe", "ParenLeft", "ParenRight", "Asterisk", "Plus", "Comma", "Minus", "Period",
    "Slash", "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "Colon", "Semicolon", "Less", "Equal", "Greater",
    "Question", "At", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P", "Q", "R", "S",
    "T", "U", "V", "W", "X", "Y", "Z", "BracketLeft", "BackSlash", "BracketRight", "AsciiCircum", "UnderScore",
    "QuoteLeft", "BraceLeft", "Bar", "BraceRight", "AsciiTilde", "Yen", "Section",
};
const size_t kGodotNameCount = sizeof kGodotNames / sizeof kGodotNames[0];

}  // namespace pcw::keys
