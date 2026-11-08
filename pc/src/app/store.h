// The pairing kept between runs: the headset's name, address, port, pin and token, as one JSON object encrypted
// for the Windows user with DPAPI (%APPDATA%\pc-windows\pairing.dat). Another user, or the file copied to another
// PC, cannot read it.
#pragma once

#include <cstdint>
#include <optional>
#include <string>

namespace pcw {

struct Pairing {
    std::string headset;  // its name
    uint32_t address = 0;
    uint16_t port = 0;
    std::string pin;
    std::string token;
};

std::optional<Pairing> load_pairing();
bool save_pairing(const Pairing& p);
void forget_pairing();

}  // namespace pcw
