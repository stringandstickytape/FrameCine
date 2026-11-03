#!/bin/bash
# Makes the test files of features_test.gd in ~/media-tests/features (needs Animated.1080p.mp4 in the local test library
# ($VRVP_LIBRARY, default ~/media-tests/library: a link to an H.264 + AAC MP4 of your own), animated_subs.mkv of
# make-test-files.sh, and the remux-only FFmpeg of build/ffmpeg-build.sh tool):
#   meta_*.mkv / .mp4     30 s of Animated.1080p.mp4 with stereo 3D / spherical metadata and chapters (tools/meta_remux.c)
#   ext/                  two videos and subtitle files next to them: UTF-8, Windows-1252, UTF-16, WebVTT, ASS, a Subs folder
#   single/               one video, with subtitle files not named after it
#   styled/               SubRip and ASS files with style tags
#   *.avi                 PCM tones for playback speed, night mode and dialogue boost
#   music/                audio-only files with tags and cover art (M4A, FLAC, WAV, AC-3)
#   letterbox/            H.264 with exact black bars (tools/pcm_h264_avi.py)
# wsl -d Ubuntu -- bash spikes/03-player/demux-test/make-feature-files.sh

set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOOL=$HOME/src/ffmpeg-tool
ZLIB=$HOME/src/ffmpeg-build-tool/zlib
LIB=${VRVP_LIBRARY:-$HOME/media-tests/library}
IN=$LIB/Animated.1080p.mp4
SUBS=$HOME/media-tests/animated_subs.mkv
OUT=$HOME/media-tests/features
[ -f "$SUBS" ] || { echo "Make $SUBS first: make-test-files.sh"; exit 1; }
mkdir -p "$OUT"

BIN=/tmp/meta_remux
gcc -O1 -o "$BIN" "$HERE/tools/meta_remux.c" -I"$TOOL/include" -L"$TOOL/lib" -L"$ZLIB" \
  -lavformat -lavcodec -lavutil -lz -lm -lpthread
D=--duration=30
"$BIN" "$IN" "$OUT/meta_sbs_chapters.mkv" $D --stereo=sbs --chapters=6
"$BIN" "$IN" "$OUT/meta_tb_inverted.mkv" $D --stereo=tb --invert
"$BIN" "$IN" "$OUT/meta_vr180.mkv" $D --stereo=sbs --projection=vr180
"$BIN" "$IN" "$OUT/meta_360_tb.mp4" $D --stereo=tb --projection=equirect
"$BIN" "$IN" "$OUT/meta_vr180.mp4" $D --stereo=sbs --projection=vr180 --chapters=3
"$BIN" "$IN" "$OUT/meta_none.mp4" $D

# Subtitle files: the same three cues (1-3 s, 5-7 s, 60-62 s) in each, with the language's own text.
rm -rf "$OUT/ext" "$OUT/single" "$OUT/styled"
mkdir -p "$OUT/ext/Subs/Film.Name.2019" "$OUT/ext/Subs/Other" "$OUT/single/Subs" "$OUT/styled"
cp "$SUBS" "$OUT/ext/Film.Name.2019.mkv"
cp "$OUT/meta_none.mp4" "$OUT/ext/Other.Film.mp4"
cp "$OUT/meta_none.mp4" "$OUT/single/My Movie (2019).mp4"
python3 - "$OUT" <<'EOF'
import sys
out = sys.argv[1]
cues = [(1, 3), (5, 7), (60, 62)]


def srt(lines):
    parts = []
    for i, ((a, b), text) in enumerate(zip(cues, lines)):
        parts.append(f"{i + 1}\n00:00:{a:02d},000 --> 00:00:{b:02d},000\n{text}\n")
    return "\n".join(parts) + "\n"


def vtt(lines):
    parts = ["WEBVTT\n"]
    for (a, b), text in zip(cues, lines):
        parts.append(f"00:00:{a:02d}.000 --> 00:00:{b:02d}.000\n{text}\n")
    return "\n".join(parts) + "\n"


def ass(lines):
    head = ("[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\n\n[V4+ Styles]\n"
            "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
            "Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H64000000,0,0,0,0,100,100,0,0,1,2,1,2,40,40,40,1\n\n[Events]\n"
            "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    return head + "".join(f"Dialogue: 0,0:00:{a:02d}.00,0:00:{b:02d}.00,Default,,0,0,0,,{{\\i1}}{t}{{\\i0}}\n" for (a, b), t in zip(cues, lines))


def write(path, text, encoding):
    with open(f"{out}/{path}", "wb") as f:
        f.write(text.encode(encoding))


ext = "ext/Film.Name.2019"
write(f"{ext}.en.srt", srt(["Hello there", "Second line", "A minute in"]), "utf-8")
write(f"{ext}.de.forced.srt", srt(["Grüße aus Köln", "Straße", "Übermorgen"]), "cp1252")
write(f"{ext}.pt-BR.srt", srt(["Olá, ação", "Coração", "Um minuto"]), "utf-16")  # With a BOM.
write(f"{ext}.fr.sdh.vtt", vtt(["[musique] Bonjour", "Deuxième", "Une minute"]), "utf-8-sig")
write(f"{ext}.en.hi.srt", srt(["[door creaks] Hello", "Second", "Minute"]), "utf-8")
write(f"{ext}.ass", ass(["Styled one", "Styled two", "Styled three"]), "utf-8")
write("ext/Other.Film.en.srt", srt(["Not this film", "No", "No"]), "utf-8")
write("ext/Subs/2_Spanish.srt", srt(["Hola", "Dos", "Un minuto"]), "utf-8")  # Two videos here: not matched.
write("ext/Subs/Film.Name.2019/3_Italian.srt", srt(["Ciao", "Due", "Un minuto"]), "utf-8")
write("ext/Subs/Other/4_Dutch.srt", srt(["Nee", "Nee", "Nee"]), "utf-8")
write("single/english.srt", srt(["Single folder", "Two", "Three"]), "utf-8")
write("single/Subs/2_English_SDH.srt", srt(["[laughs] Hi", "Two", "Three"]), "utf-8")
write("single/notes.txt", "not a subtitle\n", "utf-8")

# Styled text for read_subtitle_event()'s "styled": SubRip tags (FFmpeg turns them into ASS overrides) and an ASS
# script with two styles, a position, a margin override, bold, colour and size overrides, and \r.
write("styled/tags.srt", srt(["<b>Bold</b> and <i>italic</i>", '<font color="#ff0000">Red</font> plain', "{\\an8}Top line"]), "utf-8")
styled_ass = ("[Script Info]\nScriptType: v4.00+\nPlayResX: 1280\nPlayResY: 720\n\n[V4+ Styles]\n"
              "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
              "Style: Default,Arial,40,&H00FFFFFF,&H000000FF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,2,1,2,30,30,25,1\n"
              "Style: Sign,Verdana,30,&H0000FFFF,&H000000FF,&H00202020,&H00000000,-1,0,0,0,100,100,0,0,1,3,0,8,10,10,10,1\n\n[Events]\n"
              "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
              "Dialogue: 1,0:00:01.00,0:00:03.00,Sign,,0,0,0,,{\\pos(640,100)}Sign text\n"
              "Dialogue: 0,0:00:05.00,0:00:07.00,Default,,0,0,50,,Normal {\\b1}bold{\\b0} back\\Nsecond line\n"
              "Dialogue: 0,0:01:00.00,0:01:02.00,Default,,0,0,0,,{\\c&H0000FF&\\fs60}Red big{\\r} reset\n")
write("styled/tags.ass", styled_ass, "utf-8")
EOF
# PCM AVIs for the audio tests (48 kHz, 16-bit):
#   tone_steps.avi  20 s stereo whose tone rises by 25 Hz each second (300 Hz in second 0, 775 Hz in second 19), for the
#                   playback speed test: the frequency heard says which input second is playing, and that the pitch is
#                   kept.
#   dyn_steps.avi   24 s stereo 1 kHz, 2 s at -6 dBFS and 2 s at -36 dBFS in turn, for night mode.
#   centre_51.avi   10 s of 5.1: 1 kHz in the centre and 500 Hz in front left and right, each at -20 dBFS, nothing in the
#                   LFE and surrounds, for dialogue boost.
#   channels_51.avi 10 s of 5.1 with a tone of its own in each channel, for discrete channels.
python3 - "$OUT" <<'EOF'
import array
import math
import struct
import sys

out = sys.argv[1]
rate, chunk = 48000, 4800


def chunk_bytes(fourcc, data):
    pad = b"\0" if len(data) % 2 else b""
    return fourcc + struct.pack("<I", len(data)) + data + pad


def list_bytes(kind, data):
    return b"LIST" + struct.pack("<I", len(data) + 4) + kind + data


def write_avi(path, channels, samples):
    samples = samples.tobytes()
    block = 2 * channels
    avih = struct.pack("<IIIIIIIIII4I", 40000, rate * block, 0, 0x10, 0, 0, 1, chunk * block, 0, 0, 0, 0, 0, 0)
    strh = b"auds" + struct.pack("<IIHHIIIIIIIIhhhh", 0, 0, 0, 0, 0, block, rate * block, 0, len(samples) // block, chunk * block, 0xFFFFFFFF, block, 0, 0, 0, 0)
    strf = struct.pack("<HHIIHHH", 1, channels, rate, rate * block, block, 16, 0)
    hdrl = list_bytes(b"hdrl", chunk_bytes(b"avih", avih) + list_bytes(b"strl", chunk_bytes(b"strh", strh) + chunk_bytes(b"strf", strf)))
    movi_data = bytearray()
    index = bytearray()
    step = chunk * block
    for offset in range(0, len(samples), step):
        data = samples[offset:offset + step]
        index += b"00wb" + struct.pack("<III", 0x10, 4 + len(movi_data), len(data))
        movi_data += chunk_bytes(b"00wb", data)
    body = b"AVI " + hdrl + list_bytes(b"movi", bytes(movi_data)) + chunk_bytes(b"idx1", bytes(index))
    with open(f"{out}/{path}", "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def level(db):
    return 32767 * 10 ** (db / 20)


samples = array.array("h")
phase = 0.0
for n in range(rate * 20):
    phase += 2 * math.pi * (300 + 25 * (n // rate)) / rate
    v = int(12000 * math.sin(phase))
    samples.extend((v, v))
write_avi("tone_steps.avi", 2, samples)

samples = array.array("h")
for n in range(rate * 24):
    a = level(-6 if (n // (2 * rate)) % 2 == 0 else -36)
    v = int(a * math.sin(2 * math.pi * 1000 * n / rate))
    samples.extend((v, v))
write_avi("dyn_steps.avi", 2, samples)

samples = array.array("h")
a = level(-20)
for n in range(rate * 10):
    side = int(a * math.sin(2 * math.pi * 500 * n / rate))
    centre = int(a * math.sin(2 * math.pi * 1000 * n / rate))
    samples.extend((side, side, centre, 0, 0, 0))  # FL FR FC LFE BL BR (FFmpeg's 5.1 order).
write_avi("centre_51.avi", 6, samples)

# channels_51.avi: 10 s of 5.1, each channel its own tone at -20 dBFS (FL 300, FR 400, FC 500, LFE 60, BL 700, BR 800 Hz;
# FFmpeg reads a WAVE header without a channel mask as 5.1 with back channels), for discrete channels.
samples = array.array("h")
tones = (300, 400, 500, 60, 700, 800)
for n in range(rate * 10):
    samples.extend(int(a * math.sin(2 * math.pi * f * n / rate)) for f in tones)
write_avi("channels_51.avi", 6, samples)
EOF
# music/: audio-only files for MediaSource without video: tags and cover art (a 64x64 PNG made here), in M4A (the
# AAC of Animated.1080p.mp4), FLAC (tone_steps encoded), WAV, and raw AC-3 (from Feature.AC3.mp4 in the test library, if there).
mkdir -p "$OUT/music"
python3 - "$OUT/music/cover.png" <<'EOF'
import struct
import sys
import zlib


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff)


rows = b"".join(b"\0" + b"".join(bytes((x * 4, y * 4, 160)) for x in range(64)) for y in range(64))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
EOF
FF=("$TOOL/bin/ffmpeg" -hide_banner -loglevel error -y)
"${FF[@]}" -i "$IN" -i "$OUT/music/cover.png" -map 0:a -map 1 -c copy -disposition:v:0 attached_pic -t 20 \
  -metadata title="Test Song" -metadata artist="Test Artist" -metadata album="Test Album" -metadata track=3 "$OUT/music/aac_cover.m4a"
"${FF[@]}" -i "$OUT/tone_steps.avi" -i "$OUT/music/cover.png" -map 0:a -map 1 -c:a flac -c:v copy -disposition:v:0 attached_pic \
  -metadata title="Tone Steps" -metadata artist="Make Feature Files" "$OUT/music/tone_steps.flac"
"${FF[@]}" -i "$OUT/tone_steps.avi" -c copy "$OUT/music/tone_steps.wav"
AC3=$LIB/Feature.AC3.mp4
if [ -f "$AC3" ]; then
  "${FF[@]}" -ss 600 -i "$AC3" -map 0:a:0 -c copy -t 20 "$OUT/music/clip.ac3"
fi
# letterbox/: H.264 (I_PCM) AVIs with exact black bars, for letterbox detection.
mkdir -p "$OUT/letterbox"
python3 "$HERE/tools/pcm_h264_avi.py" "$OUT/letterbox/letterbox.avi" letterbox
python3 "$HERE/tools/pcm_h264_avi.py" "$OUT/letterbox/pillarbox.avi" pillarbox
# A self-signed certificate for the HTTPS test (tools/stream_server.py). Made here, never committed.
if [ ! -f "$OUT/test-cert.pem" ]; then
  openssl req -x509 -newkey rsa:2048 -nodes -keyout "$OUT/test-key.pem" -out "$OUT/test-cert.pem" -days 3650 \
    -subj "/CN=localhost" -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" 2>/dev/null
fi
ls -lR "$OUT" | grep -v "^total"
