# Feature ideas, scored

Every idea from the 2026-10-31 brainstorm, in one list. Each is graded 1 to 5 on four axes and ordered by the total.

| Axis | 5 | 1 |
|---|---|---|
| Simplicity | an afternoon | weeks, or blocked on something outside the app |
| Battery | no extra cost while watching | a second decoder session, a readback, or a continuous render |
| Usefulness | most viewers would use it most sessions | a party trick |
| Delight | the thing people will talk about | nobody will notice |

Scope rules: LAN features are fine. Internet multiplayer is never in scope. No trademarked names anywhere in the app. Nothing listens on the headset for AI control; the headset talks to a listener on the PC.

Areas: dev (development and AI control), lan, play (playback and picture), sound, subs, comfort, env (environments and delight), library.

| # | Score | Idea | Area | Simple | Battery | Useful | Delight | How |
|---|---|---|---|---|---|---|---|---|
| 1 | 19 | Pause when the headset comes off | comfort | 5 | 5 | 5 | 4 | Focused to visible is the signal; resume on don with a 1 s audio fade. |
| 2 | 18 | Battery versus film end | comfort | 4 | 5 | 5 | 4 | Measured drain against remaining duration: film ends 22:47, battery ends 23:20. |
| 3 | 18 | Hot-reload on the device | dev | 4 | 5 | 5 | 4 | Watch the app folder; reload shaders, environments and scripts in place without taking the headset off. |
| 4 | 18 | 3D depth slider | play | 5 | 5 | 5 | 3 | A horizontal shift between the eye rectangles in the shader; the most-asked comfort control. |
| 5 | 18 | Claude as the listener | dev | 4 | 5 | 4 | 5 | The headset sends event lines to a socket on the PC; the AI session watches it and acts. Nothing listens on the Frame. |
| 6 | 18 | Wrist clock | comfort | 4 | 5 | 4 | 5 | Look at the left controller for the time, battery and film remaining; drawn only while it faces you. |
| 7 | 17 | Resume per file | play | 4 | 5 | 5 | 3 | Resume or start over, plus a continue-watching row in the browser. |
| 8 | 17 | Director mode | dev | 3 | 5 | 4 | 5 | Subtitle text as an index: skip to the scene where a line is said. |
| 9 | 17 | PC audio sync | lan | 3 | 5 | 4 | 5 | PC plays the audio and is the master clock; the Frame plays silent and slews video by a frame. |
| 10 | 17 | Scene control port | dev | 3 | 5 | 4 | 5 | List the tree, spawn nodes, set properties, load a glTF, run a script; the AI builds things in the live room. |
| 11 | 17 | Catch-up replay | subs | 4 | 5 | 4 | 4 | One tap replays the last 10 s with subtitles forced on. |
| 12 | 17 | Lying-down mode | comfort | 4 | 5 | 4 | 4 | Screen to the ceiling, roll locked, slow head-pitch follow; one button. |
| 13 | 16 | Phone web remote | lan | 3 | 4 | 5 | 4 | QR code floats in the headset; the phone picks files, scrubs, types passwords, pastes URLs. |
| 14 | 16 | Push-to-talk to the AI | dev | 3 | 4 | 4 | 5 | Hold a button, the clip goes to the PC, gets transcribed, and comes back as actions. |
| 15 | 16 | Chapters | play | 4 | 5 | 4 | 3 | Ticks on the seek bar, chapter skip on the d-pad, titles in the overlay. |
| 16 | 16 | Screenshots over the port | dev | 4 | 5 | 4 | 3 | Per-eye and a third-person free camera, reduced size, so the AI can see what it built. |
| 17 | 16 | Sleep timer | comfort | 4 | 5 | 4 | 3 | Dim the room, fade audio over a minute, pause, save. |
| 18 | 16 | Custom skybox | env | 4 | 5 | 3 | 4 | Any equirect photo as a room. |
| 19 | 16 | Seat choice | env | 4 | 5 | 3 | 4 | Point at a seat: front row for 3D, back row for subtitles. |
| 20 | 16 | Room light follows playback | env | 5 | 5 | 3 | 3 | Dims on play, up on pause or when the menu opens. |
| 21 | 15 | Virtual cinema speakers | sound | 2 | 4 | 4 | 5 | Keep 5.1 as six channels and feed six positional players around the cinema; dialogue from the screen. |
| 22 | 15 | Still images and photo spheres | play | 3 | 4 | 4 | 4 | VR180 photos, 360 panoramas, stereo pairs, slideshow with crossfade, same meshes. |
| 23 | 15 | Permission ring for remote changes | dev | 3 | 5 | 4 | 3 | Toast with undo on every remote mutation; hold grip to allow a session for an hour. |
| 24 | 15 | A/V latency test card | sound | 4 | 5 | 4 | 2 | Beep and flash from the stub with the offset slider live, stored per refresh rate. |
| 25 | 15 | Container metadata first | play | 4 | 5 | 4 | 2 | Read the stereo and spherical metadata the demuxer exposes before guessing from the name. |
| 26 | 15 | Night mode and dialogue boost | sound | 4 | 5 | 4 | 2 | The surround decoder's dynamic-range control plus a centre gain. |
| 27 | 15 | Picture controls | play | 4 | 5 | 4 | 2 | Brightness, contrast, saturation, gamma and a dark-scene lift, remembered per environment. |
| 28 | 15 | Language memory | sound | 5 | 5 | 4 | 1 | Remember audio and subtitle language so multi-language releases open right. |
| 29 | 15 | Bias light from the picture | env | 3 | 4 | 3 | 5 | A tiny mip readback tints the room with the film. |
| 30 | 15 | Scene recipes as files | dev | 3 | 5 | 3 | 4 | Anything built over the port serialises to a scene file that loads as an environment next time. |
| 31 | 15 | Curved screen | play | 4 | 5 | 3 | 3 | Cylinder section with a radius slider; the per-vertex UV scheme supports it. |
| 32 | 15 | Haptic ticks | comfort | 4 | 5 | 3 | 3 | On seek steps and menu hover. |
| 33 | 15 | Head-follow screen | comfort | 4 | 5 | 3 | 3 | A lazy spring for fidgeters, with a pin toggle. |
| 34 | 15 | Up-next countdown | play | 4 | 5 | 3 | 3 | Poster and a countdown at the end of each file. |
| 35 | 15 | Manual zoom and pan | play | 5 | 5 | 3 | 2 | For odd aspects and burnt-in bars. |
| 36 | 15 | Wall-clock end time | comfort | 5 | 5 | 3 | 2 | Wherever a duration is shown. |
| 37 | 15 | Pre-show | env | 3 | 5 | 2 | 5 | Lights dim and curtains open on play, lights up on pause. |
| 38 | 15 | Zoom lens | play | 4 | 5 | 2 | 4 | Hold grip and trigger to magnify a region of an 8K 360 picture. |
| 39 | 15 | Intermission | env | 4 | 5 | 1 | 5 | Pause at the halfway chapter with a dancing snack; you can turn it off, but you will not. |
| 40 | 14 | Seek-bar thumbnails | play | 2 | 3 | 5 | 4 | A second decoder session decodes the nearest keyframe into a small texture above the bar. |
| 41 | 14 | Voice commands for everything | dev | 2 | 4 | 4 | 4 | Dim the lights, skip to chapter 9, move the screen up: three actions from one sentence. |
| 42 | 14 | Auto letterbox crop | play | 3 | 4 | 4 | 3 | Scan a few luma rows, snap to a cinema aspect, grow the quad. |
| 43 | 14 | Cast from the PC | lan | 3 | 4 | 4 | 3 | Drop a file on a tray app and it plays on the Frame. |
| 44 | 14 | Gapless playlist | play | 3 | 4 | 4 | 3 | Open the next file in the second session 10 s early and swap at the boundary. |
| 45 | 14 | Posters and thumbnails | library | 3 | 4 | 4 | 3 | From sidecar images, or one decoded frame cached per file. |
| 46 | 14 | Trick-play at 4x and 8x | play | 3 | 4 | 4 | 3 | Feed only keyframes to the decoder; pictures instead of a blank seek. |
| 47 | 14 | World-locked sound for 180 and 360 | sound | 3 | 4 | 4 | 3 | Binaural field stays put when you turn; head-locked for flat. |
| 48 | 14 | Built-in test lab | dev | 3 | 5 | 4 | 2 | Calibration cards for IPD, convergence and per-eye alignment; judder tests; bandwidth meter. |
| 49 | 14 | SMB host discovery | lan | 3 | 5 | 4 | 2 | Find hosts by broadcast so nobody types an address in VR. |
| 50 | 14 | External subtitle matching | subs | 4 | 5 | 4 | 1 | Find subtitle files next to the video by name and language. |
| 51 | 14 | Watch party on the LAN | lan | 2 | 4 | 3 | 5 | Two headsets, same file, one clock over UDP, each sees the other's controllers in the next seat. |
| 52 | 14 | More environments | env | 3 | 4 | 3 | 4 | Drive-in, home theatre, planetarium, dome. |
| 53 | 14 | Runtime glTF rooms | env | 3 | 4 | 3 | 4 | User environments loaded at runtime that follow the screen-anchor convention. |
| 54 | 14 | Watch-along answers | dev | 3 | 4 | 3 | 4 | Ask who that is; the answer arrives as a card at the screen's edge, from subtitles and timestamp alone. |
| 55 | 14 | Screen size in degrees | play | 4 | 5 | 3 | 2 | Fill 50 degrees of view, with large-format, living-room and in-bed presets. |
| 56 | 14 | Self-describing control API | dev | 4 | 5 | 3 | 2 | The first call returns the schema of everything else, generated from the app. |
| 57 | 14 | Stats for nerds | dev | 4 | 5 | 3 | 2 | Bitrate graph, decoder queue depth, GPU clock, power draw, thermals, frame-time histogram. |
| 58 | 14 | Subtitle depth slider | subs | 4 | 5 | 3 | 2 | Titles just in front of the screen plane; adjustable for 3D. |
| 59 | 14 | 2D from 3D | play | 5 | 5 | 3 | 1 | One eye to both views for strain or a damaged eye. |
| 60 | 14 | Sidecar JSON for the chosen mode | play | 5 | 5 | 3 | 1 | Write the user's mode next to the file so the choice travels with it. |
| 61 | 14 | Subtitle delay per track | subs | 5 | 5 | 3 | 1 | A slider, remembered with the file. |
| 62 | 14 | Floor reflection | env | 4 | 4 | 2 | 4 | One flipped quad with an alpha gradient. |
| 63 | 14 | Jog-wheel scrub | play | 3 | 5 | 2 | 4 | Twist the controller while holding the trigger to scrub. |
| 64 | 14 | Audio-only files | play | 4 | 5 | 2 | 3 | Album art or a visualiser on the screen for podcasts while lying down. |
| 65 | 14 | Dual subtitles | subs | 4 | 5 | 2 | 3 | Two tracks at once for language learning. |
| 66 | 14 | Stereo screenshots | play | 4 | 5 | 2 | 3 | Save side-by-side images of the film or the room. |
| 67 | 13 | Subtitle rendering | subs | 2 | 4 | 5 | 2 | Text and styled lines through a renderer, bitmaps direct, onto a quad layer. |
| 68 | 13 | Media-server clients | lan | 2 | 4 | 4 | 3 | Direct play from the common home media-server APIs, no transcoding. |
| 69 | 13 | Playback speed, pitch kept | play | 3 | 4 | 4 | 2 | Time-stretch in the audio path at 1.25x and 1.5x. |
| 70 | 13 | Quad layers for flat video and menu | dev | 2 | 5 | 4 | 2 | Sharper text and picture, composited by the runtime; the pending layer spike. |
| 71 | 13 | Passthrough window | comfort | 2 | 3 | 3 | 5 | The screen floats in the real room, or a small portal shows the coffee cup, if the runtime allows. |
| 72 | 13 | Hand tracking | comfort | 2 | 4 | 3 | 4 | Play, pause and point with the controllers on the sofa, if the runtime exposes it. |
| 73 | 13 | Fisheye lens profiles | play | 3 | 5 | 3 | 2 | Real polynomials for the common 190 to 220 degree lenses, not only equidistant. |
| 74 | 13 | Accessibility pack | comfort | 4 | 5 | 3 | 1 | Bigger UI scale, monocular mode, left-handed swap, forced subtitles on by default. |
| 75 | 13 | Controller battery warning | comfort | 4 | 5 | 3 | 1 | A quiet toast before a controller dies mid-film. |
| 76 | 13 | Favourites and search | library | 4 | 5 | 3 | 1 | With the on-panel keyboard. |
| 77 | 13 | Horizon correction | play | 4 | 5 | 3 | 1 | Pitch and roll trim for 180 and 360 files shot off-level. |
| 78 | 13 | Shuffle, repeat, queue editing | library | 4 | 5 | 3 | 1 | The playlist as a proper queue. |
| 79 | 13 | Edge fade for 3D | play | 4 | 5 | 2 | 2 | Soft screen edges to reduce window violations. |
| 80 | 13 | Frame step and A-B loop | play | 4 | 5 | 2 | 2 | Step with comma and period; two taps mark a loop. |
| 81 | 13 | Environment reacts to the film | env | 3 | 4 | 1 | 5 | Thunder flickers the room, bass shakes the seats through haptics. |
| 82 | 12 | Self-benchmark on first run | dev | 3 | 4 | 3 | 2 | Decode the biggest file for 10 s and report what the device can do. |
| 83 | 12 | Per-folder mode rules | play | 4 | 5 | 2 | 1 | A rule file in a folder sets the mode for everything in it. |
| 84 | 12 | Weather and time outside | env | 3 | 4 | 1 | 4 | The drive-in is at dusk when it is dusk. |
| 85 | 11 | HDR tone mapping | play | 1 | 3 | 4 | 3 | When 10-bit arrives: a tone map per environment and content light levels in the overlay. |
| 86 | 11 | More sources | lan | 2 | 4 | 3 | 2 | NFS, WebDAV, UPnP, and plain HTTP URLs. |
| 87 | 11 | Picture in picture | play | 3 | 2 | 2 | 4 | The second decoder session on a small quad: the match and the stream. |
| 88 | 11 | Live TV over the LAN | lan | 2 | 4 | 2 | 3 | Transport streams over UDP or HTTP from a tuner box. |
| 89 | 11 | Headset as a media server | lan | 3 | 4 | 2 | 2 | Serve the Frame's own storage over HTTP for uploads and screenshot pulls. |
| 90 | 11 | Light sharpen | play | 4 | 3 | 2 | 2 | A single-pass sharpen for 1080p sources on the 2160-wide panels, default off. |
| 91 | 11 | Scripted tours and kiosk mode | dev | 3 | 4 | 2 | 2 | Scene recipe plus playlist plus camera moves, running unattended. |
| 92 | 11 | Projector mode | env | 3 | 3 | 1 | 4 | A light cone with dust motes and film grain for old releases. |
| 93 | 10 | Ambisonics | sound | 2 | 3 | 2 | 3 | Decode first-order ambisonic tracks on top of the world-locked path. |
| 94 | 10 | Crossfade between items | play | 3 | 4 | 1 | 2 | Needs both sessions; mostly for slideshows and music. |
| 95 | 9 | GPU deinterlace | play | 3 | 3 | 2 | 1 | Bob or lightweight yadif in the shader for broadcast captures. |
| 96 | 9 | Spectator stream | lan | 3 | 3 | 1 | 2 | Low-res flat render served to a laptop; the platform already streams the view, so low value. |
| 97 | 8 | Refresh profile per launch | dev | 3 | 2 | 2 | 1 | 72 Hz for film, 120 Hz for sport, chosen before launch since the rate is fixed per package. |

## Notes on the scoring

- The totals are unweighted. Sort by any single column for a different cut; the simplest high-usefulness items make a good first sprint.
- Battery scores assume the mobile renderer facts from the spikes: the GPU is nearly idle on flat video, bandwidth is the cost, and a second decoder session is cheap in GPU terms but not free.
- Anything marked simplicity 1 or 2 depends on engine work in the fork, a runtime extension the platform may not expose, or a kernel the device does not have yet.
- The dev and lan rows share one piece of plumbing: a socket the headset opens to the PC. Build it once for hot-reload and everything in those two areas reuses it.
