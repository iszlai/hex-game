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
// INSTANCE_CUSTOM:
//   r  BoardLinks.Kind — 0 a lattice connector, 1 a portal tether
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

const float LINK_GLOW = 0.35;

varying vec3 tint;
varying flat float kind;

void vertex() {
	tint = COLOR.rgb;
	kind = INSTANCE_CUSTOM.r;
}

void fragment() {
	ALBEDO = tint;
	// Smoother and shinier than a tile, so the ribbon separates from the prism it
	// lies on without needing a second colour to do it.
	ROUGHNESS = 0.32;
	SPECULAR = 0.35;
	EMISSION = tint * mix(LINK_GLOW, 0.0, kind);
}
