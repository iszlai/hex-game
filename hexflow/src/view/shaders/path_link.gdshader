// The connectors of §13.3, on C-18's geometry: the bars [BoardLinks] lays between
// joined tiles, all of them in one draw call.
//
// Lit like the tiles are, so the ribbon belongs to the same board — but with a
// little emission of its own, because §13.1 asks the path to read as "a single
// continuous line of light" and a purely lit bar goes dark on the shadowed side of
// a turn. A tether does not glow: §6 calls it faint, and it describes topology
// rather than being part of the route.
//
// Colour arrives per instance from `palette.gd` (§13.2) — no literal in here, so
// §21's palettes stay a `.tres` swap.
//
// `flat_board` is §21's escape hatch, exactly as the tiles have it (C-24).
//
// INSTANCE_CUSTOM:
//   r  BoardLinks.Kind — 0 a lattice connector, 1 a portal tether
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

const float LINK_GLOW = 0.35;

// Matches [BoardTiles]' own flat path, so a ribbon lying on a tile top steps down
// with it rather than floating free of it. See `hex_prism.gdshader` for why.
const float SIDE_SHADE = 0.45;

uniform bool flat_board = false;

varying vec3 tint;
varying flat float kind;

void vertex() {
	tint = COLOR.rgb;
	kind = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 glow = tint * mix(LINK_GLOW, 0.0, kind);
	if (flat_board) {
		float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = tint * mix(SIDE_SHADE, 1.0, up) + glow;
	} else {
		ALBEDO = tint;
		// Smoother and shinier than a tile, so the ribbon separates from the prism
		// it lies on without needing a second colour to do it.
		ROUGHNESS = 0.32;
		SPECULAR = 0.35;
		EMISSION = glow;
	}
}
