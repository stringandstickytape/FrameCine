// The sky of an assistant's room (scripts/assistant/assistant_room.gd): a colour or a picture on a far sphere, and,
// named in the room document, twinkling stars (STARS) and a drifting cloud layer (CLOUDS). All procedural, from
// the direction alone: nothing to load, sharp at any resolution.
//
// Stars: one candidate per cell of a 3D grid on the direction, kept by density, placed off the cell's corners,
// brightness skewed so few are bright, a slight colour each. Drawn no smaller than a pixel (fwidth), their energy
// spread when smaller, so they neither alias nor crawl. Twinkle: each star its own rate (0.15..1.2 Hz) and phase,
// swinging by at most `twinkle` (<= 0.4): the photosensitivity ceiling (docs/assistant.md).
// Clouds: four octaves of value noise on a plane above, drifting with the wind, thinning softly to the horizon,
// lit a little brighter on top; a dither of a fraction of a level hides banding in the dark gradients.
shader_type spatial;
// Opaque and writing depth, like any far wall: with depth_draw_never the renderer sorts it with the see-through
// things, and as its centre is near the viewer it was drawn last, over every one of them.
render_mode unshaded, cull_disabled, shadows_disabled, specular_disabled, fog_disabled;

uniform vec3 sky_color : source_color = vec3(0.0);
uniform sampler2D sky_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_texture = false;
uniform float star_density = 0.5;
uniform float twinkle = 0.25;
uniform vec3 star_color : source_color = vec3(1.0);
uniform float cloud_cover = 0.4;
uniform float cloud_speed = 0.5;
uniform vec3 cloud_color : source_color = vec3(0.8, 0.83, 0.88);

const float MAX_SWING = 0.4;

varying vec3 dir;

void vertex() {
	dir = VERTEX;
}

float sky_hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float sky_noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(sky_hash(i), sky_hash(i + vec3(1, 0, 0)), f.x),
			mix(sky_hash(i + vec3(0, 1, 0)), sky_hash(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(sky_hash(i + vec3(0, 0, 1)), sky_hash(i + vec3(1, 0, 1)), f.x),
			mix(sky_hash(i + vec3(0, 1, 1)), sky_hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void fragment() {
	vec3 d = normalize(dir);
	vec3 col = sky_color;
	if (use_texture) {
		col = texture(sky_texture, UV).rgb;
	}
#if defined(STARS)
	{
		// About 0.45 degrees a cell.
		vec3 g = d * 128.0;
		vec3 cell = floor(g);
		float keep = sky_hash(cell + 11.0);
		if (keep < star_density * 0.35) {
			vec3 at = cell + 0.2 + 0.6 * vec3(sky_hash(cell + 1.7), sky_hash(cell + 3.1), sky_hash(cell + 5.3));
			// On the sphere the directions lie on, so every star is whole (not a slice through a ball off the sphere).
			at = normalize(at) * 128.0;
			float dist = length(g - at);
			float px = max(length(fwidth(g)), 1e-4);
			float core = 0.07;
			float r = max(core, px * 0.9);
			float bright = pow(sky_hash(cell + 7.9), 3.0) * 1.6 + 0.12;
			bright *= (core * core) / (r * r);
			float rate = 0.15 + 1.05 * sky_hash(cell + 9.4);
			float tw = 1.0 + clamp(twinkle, 0.0, MAX_SWING)
					* sin(6.2831853 * (rate * TIME + sky_hash(cell + 13.2)));
			float temp = sky_hash(cell + 15.8);
			vec3 tint = mix(vec3(0.8, 0.88, 1.0), vec3(1.0, 0.9, 0.75), temp);
			// Only above the horizon, fading in near it (haze).
			float up = smoothstep(-0.02, 0.12, d.y);
			col += star_color * tint * bright * tw * exp(-dist * dist / (r * r)) * up;
		}
	}
#endif
#if defined(CLOUDS)
	{
		float up = d.y;
		// The layer seen from below: a plane 1 unit up, the horizon far away.
		vec2 p = d.xz / max(up + 0.12, 0.02) * 1.6 + vec2(TIME * cloud_speed * 0.02, TIME * cloud_speed * 0.007);
		float n = 0.0;
		float a = 0.5;
		vec2 q = p;
		for (int i = 0; i < 4; i++) {
			n += a * sky_noise(vec3(q, TIME * 0.004 * float(i + 1)));
			q = q * 2.03 + vec2(1.7, 9.2);
			a *= 0.5;
		}
		n /= 0.9375;
		float c = clamp(cloud_cover, 0.0, 1.0);
		float density = smoothstep(1.0 - c - 0.12, 1.0 - c + 0.28, n);
		density *= smoothstep(0.0, 0.22, up);
		vec3 lit = mix(cloud_color * 0.62, cloud_color, smoothstep(0.35, 0.9, n));
		col = mix(col, lit, density * 0.92);
	}
#endif
	// Dither: under half a level of 8-bit noise, fixed (it does not flicker), so slow gradients do not band.
	col += (sky_hash(vec3(FRAGCOORD.xy, 61.0)) - 0.5) / 255.0;
	ALBEDO = max(col, vec3(0.0));
}
