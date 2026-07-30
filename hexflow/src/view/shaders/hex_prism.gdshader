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
// A wall carries §6's 45° hatch on its top face, in `hatch_ink` — the one cue it
// has that is neither its colour nor its height.
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

// How much darker a side face is than a top face, and how far it is then pulled
// toward `side_ink`. The pull is what makes a tile read as an object standing on
// the board instead of a fill with a dimmer edge — and C-22 needs the sides read
// as sides, because that is where a tile's height is visible at all.
const float SIDE_SHADE = 0.45;
const float SIDE_INK = 0.5;

/// A wall's 45° hatch (§6), which is the only cue it has that is neither colour
/// nor height. `wall.fill` and `cell.empty.fill` sit within 1% of each other in
/// luminance, so on a greyscale palette the hatch is what tells a wall from an
/// empty cell — height alone is a band a few pixels deep on a near-black tile.
/// Pitch is a fraction of the tile's own width, so it holds at every §4.4 size.
const int KIND_CANDIDATE = 1;
const int KIND_WALL = 4;

// §14.1: stroke alpha 0.55 to 1.0. The 3D board has no stroke, so it is the
// candidate's own highlight that travels between the two.
const float BREATHE_LOW = 0.55;
/// Sparse on purpose: the grey-box drew five thin lines across a cell, and §13.1
/// wants generous negative space. At half the period inked, a wall stops being a
/// dark quiet block and starts competing with the path for attention.
const float HATCH_PITCH = 0.36;
const float HATCH_DUTY = 0.24;

uniform bool flat_board = false;
uniform vec4 hatch_ink : source_color;
uniform vec4 side_ink : source_color;

// §14.1's candidate breathing, as a period in seconds — and **zero when it must
// not run at all**, which is what §14.5 asks for: a loop under Reduce Motion does
// not go faster, it stops, and the candidate holds the bright end of its stroke.
// One uniform rather than a period plus a flag, so the two cannot disagree.
uniform float breathe_seconds = 0.0;

varying vec3 tint;
varying float cursor;
varying flat float kind;
varying vec3 world;
varying flat float tile_width;

void vertex() {
	tint = COLOR.rgb;
	cursor = INSTANCE_CUSTOM.g;
	kind = INSTANCE_CUSTOM.r;
	// Board space, not view space: the hatch is painted on the tile, so it turns
	// with the board instead of swimming across it as the camera yaws.
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tile_width = length(MODEL_MATRIX[0].xyz);
}

void fragment() {
	// The cursor's tile lifts out of the board by its own light rather than by a
	// second colour. UV.x is 0 at the centre of the top face and 1 at the rim, so
	// the glow gathers at the edge where the outline used to be.
	vec3 glow = tint * cursor * mix(0.15, 0.6, UV.x);
	// `NORMAL` is in view space; the board's up is a world direction.
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);

	vec3 base = tint;
	if (int(kind + 0.5) == KIND_CANDIDATE) {
		// Driven by TIME rather than by a per-instance phase, which is exactly what
		// makes every candidate breathe **in phase** as §14.1 requires.
		float breath = 1.0;
		if (breathe_seconds > 0.0) {
			breath = mix(BREATHE_LOW, 1.0,
				0.5 + 0.5 * sin(TIME * TAU / breathe_seconds));
		}
		base *= breath;
	}
	if (int(kind + 0.5) == KIND_WALL && up > 0.5) {
		// 45° on the board plane is a stripe in x + z. The triangle wave and
		// `fwidth` keep the edges resolution-independent, as §13.3 does elsewhere.
		float s = (world.x + world.z) / (tile_width * HATCH_PITCH);
		float wave = abs(fract(s) - 0.5) * 2.0;
		float aa = max(fwidth(wave), 0.001);
		base = mix(base, hatch_ink.rgb,
			1.0 - smoothstep(HATCH_DUTY - aa, HATCH_DUTY + aa, wave));
	}

	// A side is its tile's own colour, darkened and then pulled toward the board's
	// edge ink, so every tile has a visible rim without any of them losing which
	// tile it is.
	vec3 side = mix(base * SIDE_SHADE, side_ink.rgb, SIDE_INK);
	vec3 face = mix(side, base, up);

	if (flat_board) {
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = face + glow;
	} else {
		ALBEDO = face;
		ROUGHNESS = 0.55;
		SPECULAR = 0.25;
		EMISSION = glow;
	}
}
