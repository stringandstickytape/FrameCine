#!/usr/bin/env python3
"""Writes a small H.264 AVI with exact black bars, for the letterbox test of features_test.gd.

There is no H.264 encoder in the build, so every macroblock is I_PCM: raw samples in a Baseline-profile IDR slice. That
is valid H.264 that any decoder takes, and the picture is exactly what is written. 640x352, 1 fps, every frame an IDR.

  pcm_h264_avi.py OUT.avi letterbox   30 frames: bars of 40 rows top and bottom (picture 640x272). Frames 0-1 are black,
                                      8-11 a dark scene (mean luma under the detector's limit), 12-15 bright over the bars
                                      too (a logo or a flash: the outlier the combined result must leave out).
  pcm_h264_avi.py OUT.avi pillarbox   20 frames: bars of 80 columns left and right (picture 480x352).
"""

import struct
import sys

WIDTH, HEIGHT = 640, 352
MBS_X, MBS_Y = WIDTH // 16, HEIGHT // 16
BLACK = 16  # Limited range.


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
    b.u(66, 8)  # Baseline.
    b.u(0xC0, 8)  # constraint_set0 and 1.
    b.u(30, 8)  # Level 3.0.
    b.ue(0)  # seq_parameter_set_id
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
    chroma = bytes([128]) * 128  # Cb then Cr, 8x8 each.
    for my in range(MBS_Y):
        for mx in range(MBS_X):
            b.ue(25)  # mb_type I_PCM
            b.align_zero()  # pcm_alignment_zero_bit
            for y in range(my * 16, my * 16 + 16):
                start = y * WIDTH + mx * 16
                b.raw(luma[start:start + 16])
            b.raw(chroma)
    b.trailing()
    return nal(3, 5, b.out)


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
    if mode == "pillarbox":
        return [picture(80, 0, WIDTH - 80, HEIGHT, 60, 160)] * 20
    raise SystemExit(f"unknown mode {mode}")


def chunk(fourcc, data):
    return fourcc + struct.pack("<I", len(data)) + data + (b"\x00" if len(data) & 1 else b"")


def chunk_list(kind, data):
    return b"LIST" + struct.pack("<I", 4 + len(data)) + kind + data


def write_avi(path, access_units):
    count = len(access_units)
    biggest = max(len(a) for a in access_units)
    avih = struct.pack("<IIIIIIIIII4I", 1000000, biggest, 0, 0x10, count, 0, 1, biggest, WIDTH, HEIGHT, 0, 0, 0, 0)
    strh = b"vids" + b"H264" + struct.pack("<IHHIIIIIIIIhhhh", 0, 0, 0, 0, 1, 1, 0, count, biggest, 0xFFFFFFFF, 0, 0, 0, WIDTH, HEIGHT)
    strf = struct.pack("<IiiHH4sIiiII", 40, WIDTH, HEIGHT, 1, 24, b"H264", WIDTH * HEIGHT * 3, 0, 0, 0, 0)
    hdrl = chunk_list(b"hdrl", chunk(b"avih", avih) + chunk_list(b"strl", chunk(b"strh", strh) + chunk(b"strf", strf)))
    movi = bytearray()
    index = bytearray()
    for au in access_units:
        index += b"00dc" + struct.pack("<III", 0x10, 4 + len(movi), len(au))  # AVIIF_KEYFRAME
        movi += chunk(b"00dc", au)
    body = b"AVI " + hdrl + chunk_list(b"movi", bytes(movi)) + chunk(b"idx1", bytes(index))
    with open(path, "wb") as f:
        f.write(b"RIFF" + struct.pack("<I", len(body)) + body)


def main():
    path, mode = sys.argv[1], sys.argv[2]
    headers = sps() + pps()
    units = [headers + idr_slice(luma, t & 1) for t, luma in enumerate(frames_for(mode))]
    write_avi(path, units)


if __name__ == "__main__":
    main()
