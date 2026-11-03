#!/usr/bin/env python3
"""Enumerate a V4L2 stateful decoder without v4l-utils (SteamOS has python3 but no v4l2-ctl).

For each /dev/video* (and /dev/video-dec0 if present) prints: querycap, coded (OUTPUT) and
decoded (CAPTURE) pixel formats with frame-size ranges, the current CAPTURE format (to see the
384x256 pre-SOURCE_CHANGE quirk), and every control with its menu entries (HEVC/H.264 profile
and level menus tell us the decoder's declared ceiling).

Usage:  python3 v4l2_enum.py [/dev/video-dec0 ...]
Read-only. Only VIDIOC_QUERY* / ENUM* / G_FMT ioctls are issued.
"""
import ctypes
import fcntl
import glob
import os
import sys

# ---- ioctl encoding (generic asm: arm64 and x86_64 agree) ----
_IOC_NRBITS, _IOC_TYPEBITS, _IOC_SIZEBITS = 8, 8, 14
_IOC_NRSHIFT = 0
_IOC_TYPESHIFT = _IOC_NRSHIFT + _IOC_NRBITS
_IOC_SIZESHIFT = _IOC_TYPESHIFT + _IOC_TYPEBITS
_IOC_DIRSHIFT = _IOC_SIZESHIFT + _IOC_SIZEBITS
_IOC_WRITE, _IOC_READ = 1, 2


def _ioc(d, t, nr, size):
    return (d << _IOC_DIRSHIFT) | (ord(t) << _IOC_TYPESHIFT) | (nr << _IOC_NRSHIFT) | (size << _IOC_SIZESHIFT)


def _ior(t, nr, st):
    return _ioc(_IOC_READ, t, nr, ctypes.sizeof(st))


def _iowr(t, nr, st):
    return _ioc(_IOC_READ | _IOC_WRITE, t, nr, ctypes.sizeof(st))


u8, u32, s32, u64, s64 = ctypes.c_uint8, ctypes.c_uint32, ctypes.c_int32, ctypes.c_uint64, ctypes.c_int64


# ---- structs (sizes checked against linux/videodev2.h: 104, 64, 44, 208, 232, 44) ----
class v4l2_capability(ctypes.Structure):
    _fields_ = [("driver", u8 * 16), ("card", u8 * 32), ("bus_info", u8 * 32),
                ("version", u32), ("capabilities", u32), ("device_caps", u32), ("reserved", u32 * 3)]


class v4l2_fmtdesc(ctypes.Structure):
    _fields_ = [("index", u32), ("type", u32), ("flags", u32), ("description", u8 * 32),
                ("pixelformat", u32), ("mbus_code", u32), ("reserved", u32 * 3)]


class v4l2_frmsize_discrete(ctypes.Structure):
    _fields_ = [("width", u32), ("height", u32)]


class v4l2_frmsize_stepwise(ctypes.Structure):
    _fields_ = [("min_width", u32), ("max_width", u32), ("step_width", u32),
                ("min_height", u32), ("max_height", u32), ("step_height", u32)]


class _frmsize_u(ctypes.Union):
    _fields_ = [("discrete", v4l2_frmsize_discrete), ("stepwise", v4l2_frmsize_stepwise)]


class v4l2_frmsizeenum(ctypes.Structure):
    _fields_ = [("index", u32), ("pixel_format", u32), ("type", u32), ("u", _frmsize_u), ("reserved", u32 * 2)]


class v4l2_plane_pix_format(ctypes.Structure):
    _pack_ = 1
    _fields_ = [("sizeimage", u32), ("bytesperline", u32), ("reserved", ctypes.c_uint16 * 6)]


class v4l2_pix_format_mplane(ctypes.Structure):
    _pack_ = 1
    _fields_ = [("width", u32), ("height", u32), ("pixelformat", u32), ("field", u32), ("colorspace", u32),
                ("plane_fmt", v4l2_plane_pix_format * 8), ("num_planes", u8), ("flags", u8),
                ("ycbcr_enc", u8), ("quantization", u8), ("xfer_func", u8), ("reserved", u8 * 7)]


class v4l2_pix_format(ctypes.Structure):
    _fields_ = [("width", u32), ("height", u32), ("pixelformat", u32), ("field", u32), ("bytesperline", u32),
                ("sizeimage", u32), ("colorspace", u32), ("priv", u32), ("flags", u32), ("ycbcr_enc", u32),
                ("quantization", u32), ("xfer_func", u32)]


class _fmt_u(ctypes.Union):
    # The kernel union also holds v4l2_window (contains pointers), so it is 8-byte aligned on
    # 64-bit and v4l2_format.fmt starts at offset 8. _align reproduces that without the struct.
    _fields_ = [("pix", v4l2_pix_format), ("pix_mp", v4l2_pix_format_mplane), ("raw_data", u8 * 200),
                ("_align", u64)]


class v4l2_format(ctypes.Structure):
    _fields_ = [("type", u32), ("fmt", _fmt_u)]


class v4l2_query_ext_ctrl(ctypes.Structure):
    _fields_ = [("id", u32), ("type", u32), ("name", ctypes.c_char * 32), ("minimum", s64), ("maximum", s64),
                ("step", u64), ("default_value", s64), ("flags", u32), ("elem_size", u32), ("elems", u32),
                ("nr_of_dims", u32), ("dims", u32 * 4), ("reserved", u32 * 32)]


class _menu_u(ctypes.Union):
    _fields_ = [("name", u8 * 32), ("value", s64)]


class v4l2_querymenu(ctypes.Structure):
    _pack_ = 1
    _fields_ = [("id", u32), ("index", u32), ("u", _menu_u), ("reserved", u32)]


for st, size in ((v4l2_capability, 104), (v4l2_fmtdesc, 64), (v4l2_frmsizeenum, 44), (v4l2_format, 208),
                 (v4l2_query_ext_ctrl, 232), (v4l2_querymenu, 44)):
    assert ctypes.sizeof(st) == size, (st.__name__, ctypes.sizeof(st), size)

VIDIOC_QUERYCAP = _ior("V", 0, v4l2_capability)
VIDIOC_ENUM_FMT = _iowr("V", 2, v4l2_fmtdesc)
VIDIOC_G_FMT = _iowr("V", 4, v4l2_format)
VIDIOC_QUERYMENU = _iowr("V", 37, v4l2_querymenu)
VIDIOC_ENUM_FRAMESIZES = _iowr("V", 74, v4l2_frmsizeenum)
VIDIOC_QUERY_EXT_CTRL = _iowr("V", 103, v4l2_query_ext_ctrl)

BUF_TYPES = {1: "CAPTURE", 2: "OUTPUT", 9: "CAPTURE_MPLANE", 10: "OUTPUT_MPLANE"}
CAP_BITS = {0x00000001: "VIDEO_CAPTURE", 0x00000002: "VIDEO_OUTPUT", 0x00001000: "VIDEO_CAPTURE_MPLANE",
            0x00002000: "VIDEO_OUTPUT_MPLANE", 0x00004000: "VIDEO_M2M_MPLANE", 0x00008000: "VIDEO_M2M",
            0x01000000: "STREAMING", 0x80000000: "DEVICE_CAPS"}
CTRL_TYPES = {1: "INT", 2: "BOOL", 3: "MENU", 4: "BUTTON", 5: "INT64", 6: "CTRL_CLASS", 7: "STRING",
              8: "BITMASK", 9: "INT_MENU", 0x100: "U8", 0x101: "U16", 0x102: "U32"}
FLAG_NEXT_CTRL, FLAG_NEXT_COMPOUND = 0x80000000, 0x40000000
FMT_FLAG_COMPRESSED, FMT_FLAG_EMULATED = 0x0001, 0x0002
FRMSIZE_DISCRETE, FRMSIZE_CONTINUOUS, FRMSIZE_STEPWISE = 1, 2, 3


def fourcc(v):
    s = bytes([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0x7F]).decode("ascii", "replace")
    return s + ("-BE" if v & 0x80000000 else "")


def cstr(arr):
    return bytes(arr).split(b"\0", 1)[0].decode("utf-8", "replace")


def ioctl(fd, req, st):
    try:
        fcntl.ioctl(fd, req, st)
        return True
    except OSError as e:
        return e


def querycap(fd):
    cap = v4l2_capability()
    r = ioctl(fd, VIDIOC_QUERYCAP, cap)
    if r is not True:
        print(f"  QUERYCAP failed: {r}")
        return None
    v = cap.version
    caps = cap.device_caps if cap.capabilities & 0x80000000 else cap.capabilities
    names = [n for b, n in CAP_BITS.items() if caps & b]
    print(f"  driver={cstr(cap.driver)!r} card={cstr(cap.card)!r} bus={cstr(cap.bus_info)!r} "
          f"kernel={v >> 16}.{(v >> 8) & 0xFF}.{v & 0xFF}")
    print(f"  device_caps=0x{caps:08x} {' '.join(names)}")
    return caps


def framesizes(fd, pixfmt):
    out = []
    for i in range(64):
        f = v4l2_frmsizeenum(index=i, pixel_format=pixfmt)
        if ioctl(fd, VIDIOC_ENUM_FRAMESIZES, f) is not True:
            break
        if f.type == FRMSIZE_DISCRETE:
            out.append(f"{f.u.discrete.width}x{f.u.discrete.height}")
        else:
            s = f.u.stepwise
            kind = "stepwise" if f.type == FRMSIZE_STEPWISE else "continuous"
            out.append(f"{kind} {s.min_width}x{s.min_height}..{s.max_width}x{s.max_height} "
                       f"step {s.step_width}x{s.step_height}")
            break
    return out


def enum_formats(fd, buftype):
    found = False
    for i in range(64):
        d = v4l2_fmtdesc(index=i, type=buftype)
        if ioctl(fd, VIDIOC_ENUM_FMT, d) is not True:
            break
        found = True
        flags = []
        if d.flags & FMT_FLAG_COMPRESSED:
            flags.append("compressed")
        if d.flags & FMT_FLAG_EMULATED:
            flags.append("emulated")
        print(f"    [{i}] {fourcc(d.pixelformat)}  {cstr(d.description)!r}  {' '.join(flags)}")
        for fs in framesizes(fd, d.pixelformat):
            print(f"         sizes: {fs}")
    if not found:
        print("    (none)")


def g_fmt(fd, buftype):
    f = v4l2_format(type=buftype)
    r = ioctl(fd, VIDIOC_G_FMT, f)
    if r is not True:
        print(f"    G_FMT failed: {r}")
        return
    if buftype in (9, 10):
        p = f.fmt.pix_mp
        planes = ", ".join(f"plane{i}: {p.plane_fmt[i].sizeimage}B bpl={p.plane_fmt[i].bytesperline}"
                           for i in range(p.num_planes))
        print(f"    {p.width}x{p.height} {fourcc(p.pixelformat)} planes={p.num_planes} ({planes}) "
              f"colorspace={p.colorspace} ycbcr_enc={p.ycbcr_enc} quant={p.quantization} xfer={p.xfer_func}")
    else:
        p = f.fmt.pix
        print(f"    {p.width}x{p.height} {fourcc(p.pixelformat)} bpl={p.bytesperline} size={p.sizeimage} "
              f"colorspace={p.colorspace}")


def menu_entries(fd, ctrl):
    out = []
    for idx in range(ctrl.minimum, ctrl.maximum + 1):
        m = v4l2_querymenu(id=ctrl.id, index=idx)
        if ioctl(fd, VIDIOC_QUERYMENU, m) is not True:
            continue  # gaps in a menu are legal: that entry is unsupported
        if ctrl.type == 9:
            out.append(f"{idx}={m.u.value}")
        else:
            out.append(f"{idx}={cstr(m.u.name)!r}")
    return out


def enum_controls(fd):
    cid = 0
    n = 0
    while True:
        c = v4l2_query_ext_ctrl(id=cid | FLAG_NEXT_CTRL | FLAG_NEXT_COMPOUND)
        if ioctl(fd, VIDIOC_QUERY_EXT_CTRL, c) is not True:
            break
        n += 1
        t = CTRL_TYPES.get(c.type, hex(c.type))
        name = c.name.decode("utf-8", "replace")
        if c.type == 6:
            print(f"    -- class 0x{c.id:08x} {name!r}")
        else:
            extra = f" elems={c.elems} elem_size={c.elem_size}" if c.elems > 1 or c.type >= 0x100 else ""
            print(f"    0x{c.id:08x} {name!r} {t} min={c.minimum} max={c.maximum} step={c.step} "
                  f"def={c.default_value} flags=0x{c.flags:x}{extra}")
            if c.type in (3, 9):
                for line in menu_entries(fd, c):
                    print(f"        {line}")
        cid = c.id
        if n > 512:
            break
    if n == 0:
        print("    (no controls, or QUERY_EXT_CTRL unsupported)")


def probe(path):
    print(f"\n#### {path}")
    try:
        real = os.path.realpath(path)
        if real != path:
            print(f"  -> {real}")
        fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
    except OSError as e:
        print(f"  open failed: {e}")
        return
    try:
        caps = querycap(fd)
        if caps is None:
            return
        for bt in (10, 2):
            if caps & (0x2000 if bt == 10 else 0x0002) or caps & (0x4000 if bt == 10 else 0x8000):
                print(f"  coded formats ({BUF_TYPES[bt]}):")
                enum_formats(fd, bt)
        for bt in (9, 1):
            if caps & (0x1000 if bt == 9 else 0x0001) or caps & (0x4000 if bt == 9 else 0x8000):
                print(f"  decoded formats ({BUF_TYPES[bt]}):")
                enum_formats(fd, bt)
                print(f"  current {BUF_TYPES[bt]} format (before any S_FMT / SOURCE_CHANGE):")
                g_fmt(fd, bt)
        print("  controls:")
        enum_controls(fd)
    finally:
        os.close(fd)


def main(argv):
    paths = argv[1:] or sorted(set(glob.glob("/dev/video*")) | set(glob.glob("/dev/video-*")))
    if not paths:
        print("no /dev/video* nodes")
        return 1
    print(f"v4l2_enum: {len(paths)} node(s): {' '.join(paths)}")
    seen = set()
    for p in paths:
        real = os.path.realpath(p)
        if real in seen:
            print(f"\n#### {p} -> {real} (already probed)")
            continue
        seen.add(real)
        probe(p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
