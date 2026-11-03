// Desktop test source (StubVideoSource): encodes a rendered RGB test card into the two NV12 planes the hardware
// decoder produces, BT.709 limited range, with the decoder's padding lines below the picture.
// Plane 0 (Y, full size) writes Y to r, g and b; plane 1 (CbCr, half size) writes Cb to r, g, b and Cr to alpha, so
// video.gdshader reads both exactly as it reads HWVideoPlaneTexture (.r and .ra).
shader_type canvas_item;
render_mode blend_disabled, unshaded;

uniform sampler2D card : filter_linear, repeat_disable;
uniform int plane = 0;
// Fraction of the rows that hold the picture; the rest is padding (written as Y = Cb = Cr = 0, which shows as
// bright green if a crop is wrong).
uniform float visible_v = 1.0;

void fragment() {
	if (UV.y > visible_v) {
		COLOR = vec4(0.0);
	} else {
		// At half size, linear filtering at the chroma sample's centre averages the 2x2 luma block (4:2:0).
		vec3 rgb = texture(card, vec2(UV.x, UV.y / visible_v)).rgb;
		float y = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
		float cb = (rgb.b - y) / 1.8556;
		float cr = (rgb.r - y) / 1.5748;
		if (plane == 0) {
			float yl = (16.0 + 219.0 * y) / 255.0;
			COLOR = vec4(yl, yl, yl, 1.0);
		} else {
			float cbl = (128.0 + 224.0 * cb) / 255.0;
			float crl = (128.0 + 224.0 * cr) / 255.0;
			COLOR = vec4(cbl, cbl, cbl, crl);
		}
	}
}
