extends SceneTree
## Plays a MediaSource at real time, headless, and prints one line: open time, how much video came through, the CPU
## time of the demux thread and of the network reader thread, and the network counters.
##   godot --headless --path . --script stream_cpu.gd -- URL_OR_PATH SECONDS [LIVE_LATENCY]
## Video packets are taken as their time comes (from the first one's PTS) and audio is mixed at the output rate, as a
## player would. Used by stream-tests.sh.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("usage: -- URL_OR_PATH SECONDS [LIVE_LATENCY]")
		quit(2)
		return
	var url: String = args[0]
	var seconds := float(args[1])
	var s := MediaSource.new()
	if args.size() > 2:
		s.live_latency = float(args[2])
	var t_open := Time.get_ticks_msec()
	if s.open(url) != OK:
		print("CPU open failed: ", s.get_last_error())
		quit(1)
		return
	t_open = Time.get_ticks_msec() - t_open
	var playback: AudioStreamPlayback = s.get_audio_stream().instantiate_playback() if s.get_audio_track() >= 0 else null
	if playback:
		playback.start(0.0)
	var rate := s.get_output_rate()
	var mixed := 0
	var packets := 0
	var bytes := 0
	var pending := {}
	var start_pts := -1.0
	var t0 := Time.get_ticks_usec()
	while true:
		var elapsed := (Time.get_ticks_usec() - t0) / 1e6
		if elapsed >= seconds:
			break
		if playback:
			while mixed < int(elapsed * rate):
				mixed += playback.mix_audio(1.0, mini(512, int(elapsed * rate) - mixed)).size()
		while true:
			if pending.is_empty():
				pending = s.read_video_packet()
				if pending.is_empty():
					break
			if start_pts < 0.0:
				start_pts = pending["pts"]
			if float(pending["pts"]) - start_pts > elapsed:
				break
			packets += 1
			bytes += (pending["data"] as PackedByteArray).size()
			pending = {}
		OS.delay_msec(5)
	var st := s.get_stats()
	print("CPU %s (%s): open %d ms; %d video packets, %.1f Mbit/s video; demux thread %.3f s, network thread %.3f s in %.0f s; waits %d, audio underruns %d, skips %d, requests %d, wake-ups %d, datagrams %d" % [
		url.get_file(), s.get_info()["network_description"], t_open, packets, bytes * 8.0 / seconds / 1e6,
		float(st["thread_cpu_seconds"]), float(st.get("net_thread_cpu_seconds", 0.0)), seconds, int(st.get("net_waits", 0)),
		int(st["audio_underruns"]), int(st.get("net_skips", 0)), int(st.get("net_requests", 0)), int(st.get("net_wakeups", 0)),
		int(st.get("net_packets", 0))])
	s.close()
	quit()
