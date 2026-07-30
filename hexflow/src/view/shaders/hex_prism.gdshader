// The board's tiles, all of them, in one draw call: §13.3's requirement, on the
// hex-prism geometry C-18 replaced its canvas SDF with.
//
// Every colour arrives per instance from `palette.gd` through the multimesh buffer
// (§13.2) — there is deliberately not a single literal colour in here, so §21's
// four alternate palettes stay a `.tres` swap with no shader change.
//
// INSTANCE_CUSTOM carries what the tile *is* rather than how it looks:
//   r  cell kind (BoardTiles.Kind)
//   g  1.0 on the cursor's cell
//   b  fraction of the way along the path, 0 at the start
//
// **`flat_board` is §21's escape hatch** (C-18, C-24). Lit, a tile's colour on
// screen is its palette colour times whatever the key light and the shadows are
// doing to it, and a player on a greyscale or high-contrast palette has no
// guarantee two states stay apart once lighting has had its way with them. With
// it on the board takes no light at all: albedo goes to zero, so every lit term —
// diffuse, specular, ambient, shadow — multiplies out to nothing, and the tile is
// emitted at its own colour instead.
//
// What survives is the bit that matters. C-22 puts the tile's *kind* in its
// height, and a genuinely flat solid would hide that: a prism whose top and sides
// are one colour is a silhouette, not a shape. So the flat path still steps the
// side faces down by a fixed fraction — fixed being the point, because it depends
// on the face's own normal rather than on where a light happens to be.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// How much darker a side face is than a top face when the board takes no light.
// Enough to read the height as height; not so much that a side goes to black on
// the high-contrast palette.
const float SIDE_SHADE = 0.45;

uniform bool flat_board = false;

varying vec3 tint;
varying float cursor;

void vertex() {
	tint = COLOR.rgb;
	cursor = INSTANCE_CUSTOM.g;
}

void fragment() {
	// The cursor's tile lifts out of the board by its own light rather than by a
	// second colour. UV.x is 0 at the centre of the top face and 1 at the rim, so
	// the glow gathers at the edge where the outline used to be.
	vec3 glow = tint * cursor * mix(0.15, 0.6, UV.x);
	if (flat_board) {
		// `NORMAL` is in view space; the board's up is a world direction.
		float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = tint * mix(SIDE_SHADE, 1.0, up) + glow;
	} else {
		ALBEDO = tint;
		ROUGHNESS = 0.55;
		SPECULAR = 0.25;
		EMISSION = glow;
	}
}
