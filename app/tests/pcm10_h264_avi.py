#!/usr/bin/env python3
"""Writes small High 10 H.264 AVIs for the app's tests (test_auto_crop.gd, test_trick_play.gd); make-feature-media.sh
runs it. A 10-bit copy of spikes/03-player/demux-test/tools/pcm_h264_avi.py: the desktop build decodes 10-bit H.264 in
software, 8-bit only on the headset's decoder.

There is no H.264 encoder in the build, so every macroblock is I_PCM: raw samples in an IDR slice. That is valid H.264
that any decoder takes, and the picture is exactly what is written. Every frame is an IDR.

  pcm10_h264_avi.py OUT.avi letterbox   640x352, 1 fps, 30 frames: bars of 40 rows top and bottom (picture 640x272).
                                        Frames 0-1 are black, 8-11 a dark scene, 12-15 bright over the bars too.
  pcm10_h264_avi.py OUT.avi long        640x352, 1 fps, 120 frames: bars of 40 rows top and bottom in every frame.
  pcm10_h264_avi.py OUT.avi pillarbox   640x352, 1 fps, 20 frames: bars of 80 columns left and right (picture 480x352).
  pcm10_h264_avi.py OUT.avi trick       160x96, 10 fps, 120 s, a bright column moving a step a second, and 48 kHz PCM
                                        audio with a 1 kHz beep at each whole second.
  pcm10_h264_avi.py OUT.avi gap_a       160x96, 10 fps, 14 s, flat dark grey (luma 60), with the beep track.
  pcm10_h264_avi.py OUT.avi gap_b       the same, light grey (luma 200).
"""

import struct
import sys

WIDTH, HEIGHT = 640, 352
MBS_X, MBS_Y = WIDTH // 16, HEIGHT // 16
BLACK = 16  # Limited range.
FPS = 1


class Bits:
    def __init__(self):
        self.out = bytearray()
        self.cur = 0
        self.n = 0

    def u(self, value, bits):
        for i in reversed(range(bits)):
            self.cur = (self.cur << 1) | ((value >> i) & 1)
            self.n += 1
            if self.n == 8:
                self.out.append(self.cur)
                self.cur = 0
                self.n = 0

    def ue(self, value):
        v = value + 1
        length = v.bit_length()
        self.u(0, length - 1)
        self.u(v, length)

    def se(self, value):
        self.ue(2 * value - 1 if value > 0 else -2 * value)

    def align_zero(self):
        while self.n:
            self.u(0, 1)

    def raw(self, data):
        assert self.n == 0
        self.out += data

    def trailing(self):
        self.u(1, 1)
        self.align_zero()


def nal(nal_ref_idc, nal_type, rbsp):
    out = bytearray(b"\x00\x00\x00\x01")
    out.append((nal_ref_idc << 5) | nal_type)
    zeros = 0
    for b in rbsp:
        if zeros == 2 and b <= 3:
            out.append(3)
            zeros = 0
        out.append(b)
        zeros = zeros + 1 if b == 0 else 0
    return bytes(out)


def sps():
    b = Bits()
    b.u(110, 8)  # High 10.
    b.u(0x00, 8)
    b.u(30, 8)  # Level 3.0.
    b.ue(0)  # seq_parameter_set_id
    b.ue(1)  # chroma_format_idc 4:2:0
    b.ue(2)  # bit_depth_luma_minus8
    b.ue(2)  # bit_depth_chroma_minus8
    b.u(0, 1)  # qpprime_y_zero_transform_bypass_flag
    b.u(0, 1)  # seq_scaling_matrix_present_flag
    b.ue(0)  # log2_max_frame_num_minus4
    b.ue(2)  # pic_order_cnt_type: output order = decoding order
    b.ue(0)  # max_num_ref_frames
    b.u(0, 1)  # gaps_in_frame_num_value_allowed_flag
    b.ue(MBS_X - 1)
    b.ue(MBS_Y - 1)
    b.u(1, 1)  # frame_mbs_only_flag
    b.u(1, 1)  # direct_8x8_inference_flag
    b.u(0, 1)  # frame_cropping_flag
    b.u(0, 1)  # vui_parameters_present_flag
    b.trailing()
    return nal(3, 7, b.out)


def pps():
    b = Bits()
    b.ue(0)  # pic_parameter_set_id
    b.ue(0)  # seq_parameter_set_id
    b.u(0, 1)  # entropy_coding_mode_flag: CAVLC
    b.u(0, 1)  # bottom_field_pic_order_in_frame_present_flag
    b.ue(0)  # num_slice_groups_minus1
    b.ue(0)  # num_ref_idx_l0_default_active_minus1
    b.ue(0)  # num_ref_idx_l1_default_active_minus1
    b.u(0, 1)  # weighted_pred_flag
    b.u(0, 2)  # weighted_bipred_idc
    b.se(0)  # pic_init_qp_minus26
    b.se(0)  # pic_init_qs_minus26
    b.se(0)  # chroma_qp_index_offset
    b.u(1, 1)  # deblocking_filter_control_present_flag
    b.u(0, 1)  # constrained_intra_pred_flag
    b.u(0, 1)  # redundant_pic_cnt_present_flag
    b.trailing()
    return nal(3, 8, b.out)


def idr_slice(luma, idr_pic_id):
    b = Bits()
    b.ue(0)  # first_mb_in_slice
    b.ue(7)  # slice_type: I (all slices)
    b.ue(0)  # pic_parameter_set_id
    b.u(0, 4)  # frame_num
    b.ue(idr_pic_id)
    b.u(0, 1)  # no_output_of_prior_pics_flag
    b.u(0, 1)  # long_term_reference_flag
    b.se(0)  # slice_qp_delta
    b.ue(1)  # disable_deblocking_filter_idc: off
    for my in range(MBS_Y):
        for mx in range(MBS_X):
            b.ue(25)  # mb_type I_PCM
            b.align_zero()  # pcm_alignment_zero_bit
            key = b"".join(bytes(luma[y * WIDTH + mx * 16:y * WIDTH + mx * 16 + 16]) for y in range(my * 16, my * 16 + 16))
            packed = _MB_CACHE.get(key)
            if packed is None:
                big = 0
                for v in key:
                    big = (big << 10) | (v << 2)
                for i in range(128):
                    big = (big << 10) | (128 << 2)
                packed = big.to_bytes(480, "big")  # 384 samples x 10 bits: byte aligned.
                _MB_CACHE[key] = packed
            b.raw(packed)
    b.trailing()
    return nal(3, 5, b.out)


_MB_CACHE = {}


def picture(left, top, right, bottom, level_low, level_high):
    """Black frame with a checkerboard (8-pixel squares) between level_low and level_high in [left, right) x [top, bottom)."""
    luma = bytearray([BLACK]) * (WIDTH * HEIGHT)
    for y in range(top, bottom):
        row = y * WIDTH
        for x in range(left, right):
            luma[row + x] = level_high if ((x >> 3) + (y >> 3)) & 1 else level_low
    return luma


def frames_for(mode):
    if mode == "letterbox":
        normal = picture(0, 40, WIDTH, HEIGHT - 40, 60, 160)
        dark = picture(0, 40, WIDTH, HEIGHT - 40, 28, 36)  # Above "lit" (26), mean 32: under the limit (36).
        flash = picture(0, 0, WIDTH, HEIGHT, 60, 160)
        black = bytearray([BLACK]) * (WIDTH * HEIGHT)
        out = []
        for t in range(30):
            out.append(black if t < 2 else dark if 8 <= t < 12 else flash if 12 <= t < 16 else normal)
        return out
    if mode == "long":
        normal = picture(0, 40, WIDTH, HEIGHT - 40, 60, 160)
        return [normal] * 120
    if mode == "pillarbox":
        return [picture(80, 0, WIDTH - 80, HEIGHT, 60, 160)] * 20
    if mode in ("gap_a", "gap_b"):
        level = 60 if mode == "gap_a" else 200
        return [picture(0, 0, WIDTH, HEIGHT, level, level)] * (14 * FPS)
    if mode == "trick":
        # 160x96 at 10 fps for 120 s, every frame a keyframe; a bright column moves one step a second.
        base = picture(0, 0, WIDTH, HEIGHT, 60, 100)
        out = []
        for s in range(120):
            f = bytearray(base)
            x0 = (s % 10) * 16
            for y in range(HEIGHT):
                f[y * WIDTH + x0:y * WIDTH + x0 + 16] = bytes([220]) * 16
            out += [f] * FPS
        return out
    raise SystemExit(f"unknown mode {mode}")


def chunk(fourcc, data):
    return fourcc + struct.pack("<I", len(data)) + data + (b"\x00" if len(data) & 1 else b"")


def chunk_list(kind, data):
    return b"LIST" + struct.pack("<I", 4 + len(data)) + kind + data


def beeps(count):
    """16-bit mono 48 kHz PCM, one chunk per video frame: a 1 kHz beep for 30 ms at each whole second, a quiet hum between."""
    import math
    per = 48000 // FPS
    out = []
    for i in range(count):
        s = bytearray()
        for n in range(per):
            t = (i * per + n) / 48000.0
            amp = 8000 if (t % 1.0) < 0.03 else 300
            s += struct.pack("<h", int(amp * math.sin(2 * math.pi * 1000 * t)))
        out.append(bytes(s))
    return out


def write_avi(path, access_units, audio=None):
    count = len(access_units)
    biggest = max(len(a) for a in access_units)
    streams = 2 if audio else 1
    avih = struct.pack("<IIIIIIIIII4I", 1000000 // FPS, biggest, 0, 0x10, count, 0, streams, biggest, WIDTH, HEIGHT, 0, 0, 0, 0)
    strh = b"vids" + b"H264" + struct.pack("<IHHIIIIIIIIhhhh", 0, 0, 0, 0, 1, FPS, 0, count, biggest, 0xFFFFFFFF, 0, 0, 0, WIDTH, HEIGHT)
    strf = struct.pack("<IiiHH4sIiiII", 40, WIDTH, HEIGHT, 1, 24, b"H264", WIDTH * HEIGHT * 3, 0, 0, 0, 0)
    strls = chunk_list(b"strl", chunk(b"strh", strh) + chunk(b"strf", strf))
    if audio:
        samples = sum(len(a) for a in audio) // 2
        ah = b"auds" + bytes(4) + struct.pack("<IHHIIIIIIIIhhhh", 0, 0, 0, 0, 2, 96000, 0, samples, len(audio[0]), 0xFFFFFFFF, 2, 0, 0, 0, 0)
        af = struct.pack("<HHIIHHH", 1, 1, 48000, 96000, 2, 16, 0)
        strls += chunk_list(b"strl", chunk(b"strh", ah) + chunk(b"strf", af))
    hdrl = chunk_list(b"hdrl", chunk(b"avih", avih) + strls)
    movi = bytearray()
    index = bytearray()
    for i, au in enumerate(access_units):
        index += b"00dc" + struct.pack("<III", 0x10, 4 + len(movi), len(au))  # AVIIF_KEYFRAME
        movi += chunk(b"00dc", au)
        if audio:
            index += b"01wb" + struct.pack("<III", 0x10, 4 + len(movi), len(audio[i]))
            movi += chunk(b"01wb", audio[i])
    body = b"AVI " + hdrl + chunk_list(b"movi", bytes(movi)) + chunk(b"idx1", bytes(index))
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def main():
    global WIDTH, HEIGHT, MBS_X, MBS_Y, FPS
    path, mode = sys.argv[1], sys.argv[2]
    small = mode in ("trick", "gap_a", "gap_b")
    if small:
        WIDTH, HEIGHT, FPS = 160, 96, 10
        MBS_X, MBS_Y = WIDTH // 16, HEIGHT // 16
    headers = sps() + pps()
    units = [headers + idr_slice(luma, t & 1) for t, luma in enumerate(frames_for(mode))]
    write_avi(path, units, beeps(len(units)) if small else None)


if __name__ == "__main__":
    main()
