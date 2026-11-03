# Steam Frame controller layout: sources

Sources for the hand-built controller mesh and label anchors in `app/scripts/xr/controller_visual.gd`. They live here,
outside `app/`, because the app names no products or brands. `app/README.md` ("Controller labels") describes the
layout in generic terms.

- Valve, Steam Frame input reference: <https://partner.steamgames.com/doc/steamhardware/steamframe/input>. It lists
  every OpenXR input path per hand, including the profile name `/interaction_profiles/valve/frame_controller_valve`.
- Valve's controller drawing:
  <https://shared.fastly.steamstatic.com/community_assets/images/steamworks_docs/english/steamframe-controllers_1.png>.
  It labels the thumbstick, view, menu, D-pad, ABXY, Steam button, dual-stage grip buttons, bumper and dual-stage
  trigger. The layout in the mesh is measured from it. The image is linked, not copied into the repository.
- Valve, Steam Frame compatibility: <https://partner.steamgames.com/doc/steamhardware/steamframe/compat>. It says the
  Oculus Touch menu button "will map to the View button at the top of the Steam Frame Controller", and it recommends
  that apps use `XR_EXT_render_model` / `XR_EXT_interaction_render_model` to show the controllers.
- Godot's profile metadata, `modules/openxr/extensions/openxr_valve_controller_extension.cpp`: A/B/X/Y and menu on
  the right hand, d-pad and view on the left, and bumper, system, trigger, squeeze and thumbstick on both.

What the drawing shows, looking down at each controller's face:

- **Right controller:** thumbstick on the inner half, A/B/X/Y diamond on the outer half (Y front, X inner, B outer,
  A back), the menu button at the front edge, the Steam button behind the diamond.
- **Left controller:** the mirror image, with the D-pad where A/B/X/Y are and the view button where menu is.
- **Both:** the bumper on the front rim of the head above the dual-stage trigger, and the dual-stage grip button on the
  inner side of the handle where it meets the head.

No source gives dimensions. The mesh assumes a face 65 mm wide and 60 mm deep and a handle tilted 40° back.
