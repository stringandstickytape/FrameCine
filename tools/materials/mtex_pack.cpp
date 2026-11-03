// Packs one material map for the app's material library (app/materials, docs/materials.md): a raw RGBA8 picture in,
// a .mtex file out, with every mip level down to 1 x 1 compressed as ASTC 8 x 8 (2 bits per texel), laid out as the
// engine's Image keeps FORMAT_ASTC_8x8 with mipmaps. The app reads the file with FileAccess and hands the bytes to
// Image.create_from_data(), so the headset's GPU samples the blocks as they are: no import step, no compression on
// the device (the export templates have no encoder).
//
// Built against the engine's own copy of the encoder (thirdparty/astcenc of the fork, Apache 2.0) by
// tools/materials/make-packer.sh.
//
//   mtex_pack KIND WIDTH HEIGHT IN.rgba OUT.mtex [EFFORT]
//     KIND    albedo  sRGB colour; alpha ignored
//             normal  a tangent-space normal map, OpenGL convention (green up): X and Y kept, X in RGB and Y in
//                     alpha (the encoder's normal mode), Z rebuilt in the shader
//             data    linear channels (ambient occlusion, roughness, metallic); alpha ignored
//     EFFORT  the encoder's effort, 0..100 (default 98, its "thorough")
//
// .mtex layout (little endian): "MTEX", version 1, block width and height (u16 each), width, height, mip count,
// flags (1 = sRGB colour, 2 = normal map), data size, then the levels from the largest down.

#include "astcenc.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

namespace {

const unsigned BLOCK = 8;

struct Level {
	unsigned w = 0;
	unsigned h = 0;
	std::vector<float> px; // RGBA, 0..1, linear light for albedo
};

float srgb_to_linear(float c) {
	return c <= 0.04045f ? c / 12.92f : std::pow((c + 0.055f) / 1.055f, 2.4f);
}

float linear_to_srgb(float c) {
	c = std::clamp(c, 0.0f, 1.0f);
	return c <= 0.0031308f ? c * 12.92f : 1.055f * std::pow(c, 1.0f / 2.4f) - 0.055f;
}

// The next level: a 2 x 2 box (edges clamped for odd sizes). Normals are averaged as vectors and made unit length
// again, so a level's normals stay normals.
Level halve(const Level &src, bool normal) {
	Level dst;
	dst.w = std::max(1u, src.w >> 1);
	dst.h = std::max(1u, src.h >> 1);
	dst.px.resize(size_t(dst.w) * dst.h * 4);
	for (unsigned y = 0; y < dst.h; y++) {
		for (unsigned x = 0; x < dst.w; x++) {
			float sum[4] = { 0, 0, 0, 0 };
			for (unsigned dy = 0; dy < 2; dy++) {
				for (unsigned dx = 0; dx < 2; dx++) {
					unsigned sx = std::min(src.w - 1, x * 2 + dx);
					unsigned sy = std::min(src.h - 1, y * 2 + dy);
					const float *p = &src.px[(size_t(sy) * src.w + sx) * 4];
					for (int c = 0; c < 4; c++) {
						sum[c] += p[c];
					}
				}
			}
			float *d = &dst.px[(size_t(y) * dst.w + x) * 4];
			for (int c = 0; c < 4; c++) {
				d[c] = sum[c] * 0.25f;
			}
			if (normal) {
				float nx = d[0] * 2.0f - 1.0f;
				float ny = d[1] * 2.0f - 1.0f;
				float nz = d[2] * 2.0f - 1.0f;
				float len = std::sqrt(nx * nx + ny * ny + nz * nz);
				if (len > 1e-5f) {
					d[0] = nx / len * 0.5f + 0.5f;
					d[1] = ny / len * 0.5f + 0.5f;
					d[2] = nz / len * 0.5f + 0.5f;
				}
			}
		}
	}
	return dst;
}

std::vector<uint8_t> to_bytes(const Level &l, bool srgb) {
	std::vector<uint8_t> out(l.px.size());
	for (size_t i = 0; i < l.px.size(); i++) {
		float v = l.px[i];
		if (srgb && (i % 4) != 3) {
			v = linear_to_srgb(v);
		}
		out[i] = uint8_t(std::lround(std::clamp(v, 0.0f, 1.0f) * 255.0f));
	}
	return out;
}

void put32(std::vector<uint8_t> &b, uint32_t v) {
	for (int i = 0; i < 4; i++) {
		b.push_back(uint8_t(v >> (8 * i)));
	}
}

int fail(const std::string &why) {
	std::fprintf(stderr, "mtex_pack: %s\n", why.c_str());
	return 1;
}

} // namespace

int main(int argc, char **argv) {
	if (argc < 6) {
		std::fprintf(stderr, "usage: mtex_pack albedo|normal|data WIDTH HEIGHT IN.rgba OUT.mtex [EFFORT]\n");
		return 2;
	}
	const std::string kind = argv[1];
	const unsigned w = unsigned(std::atoi(argv[2]));
	const unsigned h = unsigned(std::atoi(argv[3]));
	const float effort = argc > 6 ? float(std::atof(argv[6])) : ASTCENC_PRE_THOROUGH;
	const bool srgb = kind == "albedo";
	const bool normal = kind == "normal";
	if (!srgb && !normal && kind != "data") {
		return fail("kind must be albedo, normal or data");
	}
	if (w == 0 || h == 0 || w > 8192 || h > 8192) {
		return fail("bad size");
	}
	FILE *f = std::fopen(argv[4], "rb");
	if (!f) {
		return fail(std::string("can't open ") + argv[4]);
	}
	std::vector<uint8_t> raw(size_t(w) * h * 4);
	size_t got = std::fread(raw.data(), 1, raw.size(), f);
	std::fclose(f);
	if (got != raw.size()) {
		return fail("input is not WIDTH x HEIGHT x 4 bytes");
	}

	Level base;
	base.w = w;
	base.h = h;
	base.px.resize(raw.size());
	for (size_t i = 0; i < raw.size(); i++) {
		float v = raw[i] / 255.0f;
		base.px[i] = (srgb && (i % 4) != 3) ? srgb_to_linear(v) : v;
	}
	std::vector<Level> levels;
	levels.push_back(std::move(base));
	while (levels.back().w > 1 || levels.back().h > 1) {
		levels.push_back(halve(levels.back(), normal));
	}

	astcenc_config config;
	unsigned flags = normal ? ASTCENC_FLG_MAP_NORMAL : 0;
	astcenc_profile profile = srgb ? ASTCENC_PRF_LDR_SRGB : ASTCENC_PRF_LDR;
	if (astcenc_config_init(profile, BLOCK, BLOCK, 1, effort, flags, &config) != ASTCENC_SUCCESS) {
		return fail("encoder config");
	}
	unsigned threads = std::max(1u, std::thread::hardware_concurrency());
	astcenc_context *ctx = nullptr;
	astcenc_error err = astcenc_context_alloc(&config, threads, &ctx);
	if (err != ASTCENC_SUCCESS) {
		return fail(std::string("encoder context: ") + astcenc_get_error_string(err));
	}
	// Normal maps: X to RGB, Y to alpha (what the encoder's normal mode expects); others: alpha forced opaque.
	astcenc_swizzle swizzle = normal
			? astcenc_swizzle{ ASTCENC_SWZ_R, ASTCENC_SWZ_R, ASTCENC_SWZ_R, ASTCENC_SWZ_G }
			: astcenc_swizzle{ ASTCENC_SWZ_R, ASTCENC_SWZ_G, ASTCENC_SWZ_B, ASTCENC_SWZ_1 };

	std::vector<uint8_t> data;
	for (const Level &l : levels) {
		std::vector<uint8_t> bytes = to_bytes(l, srgb);
		void *slice = bytes.data();
		astcenc_image img{ l.w, l.h, 1, ASTCENC_TYPE_U8, &slice };
		size_t blocks = size_t((l.w + BLOCK - 1) / BLOCK) * ((l.h + BLOCK - 1) / BLOCK);
		std::vector<uint8_t> out(blocks * 16);
		std::vector<std::thread> pool;
		std::vector<astcenc_error> errors(threads, ASTCENC_SUCCESS);
		for (unsigned t = 0; t < threads; t++) {
			pool.emplace_back([&, t]() {
				errors[t] = astcenc_compress_image(ctx, &img, &swizzle, out.data(), out.size(), t);
			});
		}
		for (std::thread &t : pool) {
			t.join();
		}
		for (astcenc_error e : errors) {
			if (e != ASTCENC_SUCCESS) {
				return fail(std::string("compress: ") + astcenc_get_error_string(e));
			}
		}
		astcenc_compress_reset(ctx);
		data.insert(data.end(), out.begin(), out.end());
	}
	astcenc_context_free(ctx);

	std::vector<uint8_t> file = { 'M', 'T', 'E', 'X' };
	put32(file, 1);
	put32(file, BLOCK | (BLOCK << 16));
	put32(file, w);
	put32(file, h);
	put32(file, uint32_t(levels.size()));
	put32(file, (srgb ? 1u : 0u) | (normal ? 2u : 0u));
	put32(file, uint32_t(data.size()));
	file.insert(file.end(), data.begin(), data.end());
	FILE *o = std::fopen(argv[5], "wb");
	if (!o || std::fwrite(file.data(), 1, file.size(), o) != file.size()) {
		return fail(std::string("can't write ") + argv[5]);
	}
	std::fclose(o);
	std::printf("%s %ux%u, %zu levels, %zu bytes\n", argv[5], w, h, levels.size(), file.size());
	return 0;
}
