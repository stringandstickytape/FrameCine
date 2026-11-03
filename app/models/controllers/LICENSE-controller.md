# Licence of the controller models

Derived from Valve Corporation's Steam Frame controller CAD (gitlab.steamos.cloud/SteamHardware/SteamFrame),
© Valve Corporation, used under CC BY-NC-SA 4.0; this derived model is likewise CC BY-NC-SA 4.0; no endorsement by
Valve implied.

## What this covers

Every file in this folder: `left_controller.glb`, `right_controller.glb`, `left_controller_menu.png`,
`left_controller_window.png`, `right_controller_menu.png`, `right_controller_window.png` and `controllers.json`.
They are licensed under the Creative Commons Attribution-NonCommercial-ShareAlike 4.0 International licence:
https://creativecommons.org/licenses/by-nc-sa/4.0/. The rest of this repository is under its own licence; these
files are not.

## Source

`documents-controller/Valve_Steam_Frame_Controller_20260925.zip` in https://gitlab.steamos.cloud/SteamHardware/SteamFrame
(STEP files `Valve_Steam_Frame_Controller_L_20260926.stp`, `..._R_20260926.stp` and the battery door files),
released by Valve Corporation under CC BY-NC-SA 4.0 (`license.txt` in that repository). Valve's terms also ask that
the materials are not used for commercial purposes, and that no association with or endorsement by Valve is claimed
or implied. Neither is.

## Changes made

- Tessellated from the STEP solids and decimated to about 4,700 to 5,000 triangles per controller.
- Split into parts by surface (body, battery door, thumbstick, trigger, grip button, face buttons, d-pad).
- Moved and rotated to fit the controller pose the headset's runtime uses (registered to its render model).
- UV-unwrapped, given flat dark plastic colours, and printed with this app's control legends and the face button
  letters (one texture per app state).

The scripts that make these files are in `app/tools/controller_model/`. Valve's STEP files are not in this
repository.
