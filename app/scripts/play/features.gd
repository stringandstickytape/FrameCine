extends Node

## The playback features hub (docs/features.md). main.gd creates it as "Features" before the menu's setup, so the
## menu (or the pane) reaches every feature as main.features.<name>. Each feature is a small node or helper with
## properties, signals and its own settings section; this node only creates them, hands them `main`, and offers a
## few shared conveniences. Nothing here is required by the core: delete the hub and playback still works.
##
## Features:
##   end_time   scripts/play/end_time.gd (static): "ends 23:20" for a remaining duration (#36)
##   battery    scripts/comfort/battery_forecast.gd: battery end versus film end, forecast_changed(info) (#2)
##   depth      scripts/play/stereo_depth.gd: 3D depth shift, per file and global (#4)
##   resume     scripts/play/resume.gd: resume per file, continue-watching data (#7)
##   subtitles  scripts/play/subtitles.gd: tracks, on/off, the lines now; the renderer below the picture (#67, #65)
##   catch_up   scripts/play/catch_up.gd: replay the last 10 s with subtitles forced on (#11)
##   chapters   scripts/play/chapters.gd: chapter list, skip, titles, seek-bar ticks (#15)
##   room_light scripts/env/room_light.gd: the user's room light times feature factors (sleep, playback)
##   sleep      scripts/comfort/sleep_timer.gd: dim, fade out, pause, save (#17)
##   light_follow scripts/env/light_follow.gd: the room dims while playing, up on pause or menu (#20)
##   picture    scripts/play/picture_controls.gd: brightness, contrast, saturation, gamma, lift, sharpen per environment
##              (#27, #90)
##   languages  scripts/play/language_memory.gd: remembered audio and subtitle languages (#28)
##   curve      scripts/play/curved_screen.gd: the flat screen as a cylinder section, radius per environment (#31)
##   haptics    scripts/comfort/haptics.gd: ticks on seek steps and menu hover (#32)
##   zoom       scripts/play/zoom_pan.gd: manual zoom and pan, per file (#35)
##   two_d      scripts/play/two_d.gd: one eye's picture to both views (#59)
##   horizon    scripts/play/horizon.gd: pitch and roll trim for 180 / 360, per file (#77)
##   edge_fade  scripts/play/edge_fade.gd: soft screen edges for flat 3D (#79)
##   sub_delay  scripts/play/subtitle_delay.gd: subtitle timing per file and track (#61)
##   sidecar    scripts/play/sidecar.gd: the chosen mode written next to the file (#60)
##   queue      scripts/play/play_queue.gd: shuffle, repeat, queue editing on main.playlist (#78)
##   step_loop  scripts/play/frame_step_loop.gd: frame step and A-B loop (#80)
##   library    scripts/play/favourites_search.gd: favourites and search, the data side (#76)
##   access     scripts/comfort/accessibility.gd: UI scale, left-handed, monocular, subtitles always on (#74)
##   sub_files  scripts/play/external_subtitles.gd: subtitle files next to the video, loaded as tracks (#50)
##   speed      scripts/play/playback_speed.gd: 0.5x to 2x with the pitch kept (#69)
##   hdr        scripts/play/hdr_tone_map.gd: colour matrix and range, HDR (PQ, HLG) tone mapped to the display (#85)
##   slideshow  scripts/play/slideshow.gd: pictures one after another with a crossfade (#22; image_source.gd)
##   reflection scripts/env/floor_reflection.gd: the screen's reflection on the floor (#62)
##   pose       scripts/comfort/screen_pose.gd: lying down (#12), head-follow screen with a pin (#33)
##   angle      scripts/comfort/screen_angle.gd: screen size in degrees, presets (#55)
##   seat       scripts/comfort/seat_choice.gd: sit elsewhere in the room (#19)
##   up_next    scripts/play/up_next.gd: the countdown card to the next file (#34)
##   preshow    scripts/env/preshow.gd: curtains open on play, close at the end (#37)
##   intermission scripts/play/intermission.gd: a pause at the middle chapter of long films (#39)
##   jog        scripts/play/jog_wheel.gd: circle the stick to scrub (#63)
##   screenshot scripts/play/stereo_screenshot.gd: the frame as a stereo picture (#66)
##   lens       scripts/play/fisheye_lens.gd: fisheye lens profiles, per file and default (#73)
##   dual_fisheye scripts/play/dual_fisheye.gd: dual fisheye 360 lens profiles (a 360 camera's, generic) and alignment
##   folder_modes scripts/play/folder_modes.gd: a mode per folder for files without their own (#83)
##   deinterlace scripts/play/deinterlace.gd: GPU bob or edge deinterlace for interlaced video (#95)
##   speakers   scripts/play/cinema_speakers.gd: each audio channel from its place in the room (#21, #47)
##   bias       scripts/env/bias_light.gd: the screen's light on the room takes the picture's colour (#29)
##   night      scripts/play/night_mode.gd: night mode (levelled loudness) and dialogue boost (#26)
##   react      scripts/env/film_react.gd: bass pulses in the controllers, room flashes on loud moments (#81)
##   projector  scripts/env/projector.gd: a projector's beam with dust motes, film grain, gate weave (#92)
##   time_of_day scripts/env/time_of_day.gd: the outdoor rooms' sky from the clock and a latitude (#84)
##   gaze       scripts/xr/eye_gaze.gd: where the viewer looks (calibrated), the look-and-pull calibration, the pip
##   zoom_lens  scripts/play/zoom_lens.gd: grip + trigger magnifies the aimed part of a 180 / 360 picture (#38)
##   latency    scripts/play/av_latency.gd: the A/V offset per display refresh rate (#24; lab://av_sync)
##   auto_crop  scripts/play/auto_crop.gd: crop letterbox / pillarbox bars, the screen grows to keep its height (#42)
##   trick      scripts/play/trick_play.gd: hold the stick right to scan at 4x, then 8x, pictures shown (#46)
##   live       scripts/play/live_stream.gd: udp:// and length-less HTTP streams, no seeking, latency setting
##   gapless    scripts/play/gapless.gd: the next file opens behind the current one and takes over at its end (#44)
##   pip        scripts/play/picture_in_picture.gd: a second film, silent, in a corner of the screen; swap (#87)
##   thumbs     scripts/play/seek_thumbnails.gd: pictures for the seek bar from a second session (#40), off by default
##   crossfade  scripts/play/crossfade.gd: music and videos overlap into the next item (#94), off by default
##   hwvideo    scripts/play/hw_video.gd: which way 10-bit video plays (P010, Q10C or software; read-only), hw_vp9

const EndTime := preload("res://scripts/play/end_time.gd")
const BatteryForecast := preload("res://scripts/comfort/battery_forecast.gd")
const StereoDepth := preload("res://scripts/play/stereo_depth.gd")
const Resume := preload("res://scripts/play/resume.gd")
const Subtitles := preload("res://scripts/play/subtitles.gd")
const CatchUp := preload("res://scripts/play/catch_up.gd")
const Chapters := preload("res://scripts/play/chapters.gd")
const RoomLight := preload("res://scripts/env/room_light.gd")
const SleepTimer := preload("res://scripts/comfort/sleep_timer.gd")
const LightFollow := preload("res://scripts/env/light_follow.gd")
const PictureControls := preload("res://scripts/play/picture_controls.gd")
const LanguageMemory := preload("res://scripts/play/language_memory.gd")
const CurvedScreen := preload("res://scripts/play/curved_screen.gd")
const Haptics := preload("res://scripts/comfort/haptics.gd")
const ZoomPan := preload("res://scripts/play/zoom_pan.gd")
const TwoD := preload("res://scripts/play/two_d.gd")
const Horizon := preload("res://scripts/play/horizon.gd")
const EdgeFade := preload("res://scripts/play/edge_fade.gd")
const SubtitleDelay := preload("res://scripts/play/subtitle_delay.gd")
const Sidecar := preload("res://scripts/play/sidecar.gd")
const PlayQueue := preload("res://scripts/play/play_queue.gd")
const FrameStepLoop := preload("res://scripts/play/frame_step_loop.gd")
const FavouritesSearch := preload("res://scripts/play/favourites_search.gd")
const Accessibility := preload("res://scripts/comfort/accessibility.gd")
const ExternalSubtitles := preload("res://scripts/play/external_subtitles.gd")
const PlaybackSpeed := preload("res://scripts/play/playback_speed.gd")
const HdrToneMap := preload("res://scripts/play/hdr_tone_map.gd")
const Slideshow := preload("res://scripts/play/slideshow.gd")
const FloorReflection := preload("res://scripts/env/floor_reflection.gd")
const ScreenPose := preload("res://scripts/comfort/screen_pose.gd")
const ScreenAngle := preload("res://scripts/comfort/screen_angle.gd")
const SeatChoice := preload("res://scripts/comfort/seat_choice.gd")
const UpNext := preload("res://scripts/play/up_next.gd")
const Preshow := preload("res://scripts/env/preshow.gd")
const Intermission := preload("res://scripts/play/intermission.gd")
const JogWheel := preload("res://scripts/play/jog_wheel.gd")
const StereoScreenshot := preload("res://scripts/play/stereo_screenshot.gd")
const FisheyeLens := preload("res://scripts/play/fisheye_lens.gd")
const DualFisheye := preload("res://scripts/play/dual_fisheye.gd")
const FolderModes := preload("res://scripts/play/folder_modes.gd")
const Deinterlace := preload("res://scripts/play/deinterlace.gd")
const CinemaSpeakers := preload("res://scripts/play/cinema_speakers.gd")
const BiasLight := preload("res://scripts/env/bias_light.gd")
const NightMode := preload("res://scripts/play/night_mode.gd")
const FilmReact := preload("res://scripts/env/film_react.gd")
const Projector := preload("res://scripts/env/projector.gd")
const TimeOfDay := preload("res://scripts/env/time_of_day.gd")
const ZoomLens := preload("res://scripts/play/zoom_lens.gd")
const EyeGaze := preload("res://scripts/xr/eye_gaze.gd")
const AvLatency := preload("res://scripts/play/av_latency.gd")
const AutoCrop := preload("res://scripts/play/auto_crop.gd")
const TrickPlay := preload("res://scripts/play/trick_play.gd")
const LiveStream := preload("res://scripts/play/live_stream.gd")
const Gapless := preload("res://scripts/play/gapless.gd")
const PictureInPicture := preload("res://scripts/play/picture_in_picture.gd")
const SeekThumbnails := preload("res://scripts/play/seek_thumbnails.gd")
const Crossfade := preload("res://scripts/play/crossfade.gd")
const MusicSource := preload("res://scripts/play/music_source.gd")
const HwVideo := preload("res://scripts/play/hw_video.gd")

## The app core (scripts/main.gd). Untyped: main.gd preloads this script, so a typed reference would be circular.
var main: Node3D
var battery: BatteryForecast
var depth: StereoDepth
var resume: Resume
var subtitles: Subtitles
var catch_up: CatchUp
var chapters: Chapters
var room_light: RoomLight
var sleep: SleepTimer
var light_follow: LightFollow
var picture: PictureControls
var languages: LanguageMemory
var curve: CurvedScreen
var haptics: Haptics
var zoom: ZoomPan
var two_d: TwoD
var horizon: Horizon
var edge_fade: EdgeFade
var sub_delay: SubtitleDelay
var sidecar: Sidecar
var queue: PlayQueue
var step_loop: FrameStepLoop
var library: FavouritesSearch
var access: Accessibility
var sub_files: ExternalSubtitles
var speed: PlaybackSpeed
var hdr: HdrToneMap
var slideshow: Slideshow
var reflection: FloorReflection
var pose: ScreenPose
var angle: ScreenAngle
var seat: SeatChoice
var up_next: UpNext
var preshow: Preshow
var intermission: Intermission
var jog: JogWheel
var screenshot: StereoScreenshot
var lens: FisheyeLens
var dual_fisheye: DualFisheye
var folder_modes: FolderModes
var deinterlace: Deinterlace
var speakers: CinemaSpeakers
var bias: BiasLight
var night: NightMode
var react: FilmReact
var projector: Projector
var time_of_day: TimeOfDay
var zoom_lens: ZoomLens
var gaze: EyeGaze
var latency: AvLatency
var auto_crop: AutoCrop
var trick: TrickPlay
var live: LiveStream
var gapless: Gapless
var pip: PictureInPicture
var thumbs: SeekThumbnails
var crossfade: Crossfade
var hwvideo: HwVideo


func _ready() -> void:
	EndTime.use_24h = bool(main.settings.get_value("display", "clock_24h", true))
	var vis := str(main.settings.get_value("music", "visualiser", "bars"))
	MusicSource.style = vis if vis in MusicSource.STYLES else "bars"
	battery = _add(BatteryForecast.new(), "Battery")
	depth = _add(StereoDepth.new(), "StereoDepth")
	resume = _add(Resume.new(), "Resume")
	subtitles = _add(Subtitles.new(), "Subtitles")
	catch_up = _add(CatchUp.new(), "CatchUp")
	chapters = _add(Chapters.new(), "Chapters")
	room_light = _add(RoomLight.new(), "RoomLight")
	sleep = _add(SleepTimer.new(), "SleepTimer")
	light_follow = _add(LightFollow.new(), "LightFollow")
	picture = _add(PictureControls.new(), "Picture")
	languages = _add(LanguageMemory.new(), "Languages")
	curve = _add(CurvedScreen.new(), "CurvedScreen")
	haptics = _add(Haptics.new(), "Haptics")
	zoom = _add(ZoomPan.new(), "ZoomPan")
	two_d = _add(TwoD.new(), "TwoD")
	horizon = _add(Horizon.new(), "Horizon")
	edge_fade = _add(EdgeFade.new(), "EdgeFade")
	sub_delay = _add(SubtitleDelay.new(), "SubtitleDelay")
	sidecar = _add(Sidecar.new(), "Sidecar")
	queue = _add(PlayQueue.new(), "Queue")
	step_loop = _add(FrameStepLoop.new(), "StepLoop")
	library = _add(FavouritesSearch.new(), "Library")
	access = _add(Accessibility.new(), "Accessibility")
	sub_files = _add(ExternalSubtitles.new(), "SubtitleFiles")
	speed = _add(PlaybackSpeed.new(), "PlaybackSpeed")
	hdr = _add(HdrToneMap.new(), "HdrToneMap")
	slideshow = _add(Slideshow.new(), "Slideshow")
	reflection = _add(FloorReflection.new(), "FloorReflection")
	pose = _add(ScreenPose.new(), "ScreenPose")
	angle = _add(ScreenAngle.new(), "ScreenAngle")
	seat = _add(SeatChoice.new(), "SeatChoice")
	up_next = _add(UpNext.new(), "UpNext")
	preshow = _add(Preshow.new(), "Preshow")
	intermission = _add(Intermission.new(), "Intermission")
	jog = _add(JogWheel.new(), "JogWheel")
	screenshot = _add(StereoScreenshot.new(), "StereoScreenshot")
	lens = _add(FisheyeLens.new(), "FisheyeLens")
	dual_fisheye = _add(DualFisheye.new(), "DualFisheye")
	folder_modes = _add(FolderModes.new(), "FolderModes")
	deinterlace = _add(Deinterlace.new(), "Deinterlace")
	speakers = _add(CinemaSpeakers.new(), "CinemaSpeakers")
	bias = _add(BiasLight.new(), "BiasLight")
	night = _add(NightMode.new(), "NightMode")
	react = _add(FilmReact.new(), "FilmReact")
	projector = _add(Projector.new(), "Projector")
	time_of_day = _add(TimeOfDay.new(), "TimeOfDay")
	zoom_lens = _add(ZoomLens.new(), "ZoomLens")
	gaze = _add(EyeGaze.new(), "EyeGaze")
	latency = _add(AvLatency.new(), "AvLatency")
	auto_crop = _add(AutoCrop.new(), "AutoCrop")
	trick = _add(TrickPlay.new(), "TrickPlay")
	live = _add(LiveStream.new(), "LiveStream")
	gapless = _add(Gapless.new(), "Gapless")
	pip = _add(PictureInPicture.new(), "PictureInPicture")
	thumbs = _add(SeekThumbnails.new(), "SeekThumbnails")
	crossfade = _add(Crossfade.new(), "Crossfade")
	hwvideo = _add(HwVideo.new(), "HwVideo")


func _add(node: Node, node_name: String) -> Node:
	node.name = node_name
	if "main" in node:
		node.set("main", main)
	add_child(node)
	return node


## Seconds left in what is playing, or 0 when unknown (no source, no duration, a window).
func remaining() -> float:
	var p: Node = main.player
	if not p.has_source():
		return 0.0
	var d: float = p.get_duration()
	return maxf(d - p.get_position(), 0.0) if d > 0.0 else 0.0


## Real seconds until the end at the playback speed (#69).
func remaining_real() -> float:
	return remaining() / (speed.speed if speed != null else 1.0)


## "ends 23:20" for what is playing (at the playback speed), or "" (nothing open, no duration).
func end_text() -> String:
	return EndTime.format_end(remaining(), speed.speed if speed != null else 1.0)


## The music card's visualiser (#64): one of MusicSource.STYLES ("bars", "mirror", "line", "radial", "off"; names for
## the pane in MusicSource.STYLE_NAMES). [music] visualiser, default "bars". Applies at once to the card showing.
func visualiser() -> String:
	return MusicSource.style


func set_visualiser(s: String) -> void:
	if not s in MusicSource.STYLES:
		return
	MusicSource.style = s
	main.settings.set_value("music", "visualiser", null if s == "bars" else s)


## One line of feature state for the overlay ("chapter 3/12 Title  |  sleep in 23 min ..."), or "".
func status_line() -> String:
	var parts: Array[String] = []
	if chapters.current >= 0:
		parts.append("chapter " + chapters.title_text().left(40))
	if sleep.active:
		parts.append(sleep.status_text())
	if step_loop.text() != "":
		parts.append(step_loop.text())
	if speed.text() != "":
		parts.append("speed " + speed.text())
	if hdr.is_hdr():
		parts.append("HDR10" if int(hdr.current["transfer"]) == hdr.TRANSFER_PQ else "HLG")
	if trick.speed > 0.0:
		parts.append("scan %dx" % int(trick.speed))
	if live.live:
		parts.append("LIVE (%.1f s buffer)" % live.latency)
	return "  |  ".join(parts)


## The battery line for the overlay: "battery 72 %, ends 23:20 | film ends 22:47", or "no battery".
func battery_text() -> String:
	var f := battery.get_forecast()
	if not bool(f.get("available", false)):
		return "no battery"
	return str(f["text"])
