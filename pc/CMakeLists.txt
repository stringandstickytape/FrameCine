# pc-windows: the PC half of "PC windows in the headset" (docs/pc-windows.md). Windows only, MSVC, no third-party
# libraries. Build: see README.md (pc/build.cmd does it all).
cmake_minimum_required(VERSION 3.20)
project(pc_windows LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# The static runtime, so the folder holds one exe and nothing else to install.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")

if(NOT MSVC)
  message(FATAL_ERROR "pc-windows builds with MSVC (Visual Studio 2022 or later)")
endif()

# /W4 for our code; the SDK's own headers (angle brackets) are not ours to fix.
add_compile_options(/W4 /WX /permissive- /utf-8 /EHsc /Zc:__cplusplus /MP /external:anglebrackets /external:W0
                    /bigobj)
add_compile_definitions(UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX _WIN32_WINNT=0x0A00 WINVER=0x0A00)

add_library(pcw_core STATIC
  src/core/json.cpp
  src/core/keys.cpp
  src/core/mapping.cpp
  src/core/media.cpp
  src/core/protocol.cpp)
target_include_directories(pcw_core PUBLIC src/core)

add_executable(pc-windows WIN32
  src/app/main.cpp
  src/app/audio_stream.cpp
  src/app/capture.cpp
  src/app/control.cpp
  src/app/discovery.cpp
  src/app/input.cpp
  src/app/log.cpp
  src/app/net.cpp
  src/app/store.cpp
  src/app/tls.cpp
  src/app/ui.cpp
  src/app/util.cpp
  src/app/video_encoder.cpp
  src/app/video_stream.cpp
  src/app/window_list.cpp
  src/app/pc-windows.rc)
target_link_libraries(pc-windows PRIVATE pcw_core
  d3d11 dxgi dwmapi mfplat mfuuid mf wmcodecdspuuid secur32 crypt32 bcrypt ws2_32 iphlpapi windowscodecs
  windowsapp ole32 oleaut32 shell32 shlwapi user32 gdi32 comctl32 winmm)
# The manifest in the .rc sets per-monitor-v2 DPI awareness and common controls 6.
set_target_properties(pc-windows PROPERTIES LINK_FLAGS "/MANIFEST:NO")

# Tests: the unit tests (ctest), and the test window the end-to-end test captures and types into
# (tools/pc_windows_fake_headset.py).
enable_testing()
add_executable(pcw_unit_tests tests/unit_tests.cpp)
target_link_libraries(pcw_unit_tests PRIVATE pcw_core)
add_test(NAME unit COMMAND pcw_unit_tests)

add_executable(pcw-testwin WIN32 tests/testwin.cpp tests/testwin.rc)
target_link_libraries(pcw-testwin PRIVATE user32 gdi32 dwmapi winmm)
set_target_properties(pcw-testwin PROPERTIES LINK_FLAGS "/MANIFEST:NO")
