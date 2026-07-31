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
const int KIND_PATH = 2;
const int KIND_START = 3;
const int KIND_WALL = 4;

// §14.1: stroke alpha 0.55 to 1.0. The 3D board has no stroke, so it is the
// candidate's own highlight that travels between the two.
// How far the candidate breathing dips. Shallow: §14.1 asks candidates to breathe
// and it never said how deep, and at 0.55 a board offering four moves had four
// tiles swinging through half their brightness beside a cursor doing the same —
// two loud signals, and no way to tell which one was the answer. The cursor's glow
// is the louder cue now and this is a pulse under it.
const float BREATHE_LOW = 0.88;
/// Sparse on purpose: the grey-box drew five thin lines across a cell, and §13.1
/// wants generous negative space. At half the period inked, a wall stops being a
/// dark quiet block and starts competing with the path for attention.
const float HATCH_PITCH = 0.36;
const float HATCH_DUTY = 0.24;

/// §13.6's board material (C-26). Sampled in **board space** rather than in UV, so
/// the grain belongs to the board and turns with it — exactly like the wall hatch
/// above, and for the same reason: a texture pinned to the screen swims across the
/// tiles every time the camera moves to a new 60° stop.
///
/// It is a *value* map, mid-grey at rest, and it multiplies. That keeps §13.2
/// intact: the tile's colour is still entirely the palette's, and the material
/// only says how the light falls on it.
uniform sampler2D grain_map : source_color, filter_linear_mipmap, repeat_enable;
uniform float grain_strength = 0.0;
const float GRAIN_SCALE = 2.2;

// The grain is sampled **per tile**, not across the board.
//
// It used to be one continuous sheet that the tiles were cut out of, and that is
// exactly what it looked like: a textured table with hexagons scored into it. A
// board of slabs wants each slab to be its own piece of stone — its own grain
// direction, its own patch of the map — which is the difference between a surface
// with tiles drawn on it and tiles lying on a surface.
//
// The variation is hashed from the tile's own origin rather than carried in
// INSTANCE_CUSTOM, whose four channels are all spoken for. That also makes it
// stable: a tile's grain is a function of where it is, so it cannot crawl when the
// board rebuilds or shimmer when the camera turns.
const float GRAIN_ROTATION = 6.2831853;

vec2 grain_hash(vec2 seed) {
	// Two decorrelated values in 0..1. Deterministic, and no engine RNG is involved
	// anywhere near it (C2).
	float a = fract(sin(dot(seed, vec2(12.9898, 78.233))) * 43758.5453);
	float b = fract(sin(dot(seed, vec2(39.3468, 11.1357))) * 24634.6345);
	return vec2(a, b);
}

uniform bool flat_board = false;
uniform vec4 hatch_ink : source_color;
uniform vec4 side_ink : source_color;

// A drawn board outlines its pieces and insets their faces, and those two lines
// are most of why one reads as an object and a shaded prism reads as a render.
// Both ride `UV.x`, the radial fraction — 0 at the centre of the top face, 1 at
// the outer rim — so they follow the hexagon exactly and cost no geometry.
//
// The ink is the palette's own outline token, the one C-23 gives every modifier
// mark. Reused rather than added to: it is *the* ink of this board, it already
// inverts with the surfaces in a light palette, and a second token would be a
// second thing to keep in step for no gain.
uniform vec4 tile_ink : source_color;

// C-26's drawn tile top (optional): a 2x2 atlas of hexagon faces, sampled across
// the face rather than tiled over it, so what the player sees on a tile is a
// *drawing* — hand-drawn outline, rim, light-and-shadow split, halftone screening
// the shadow — instead of a lit polygon with a computed ring on it.
//
// A value map like everything else here, so the palette still supplies the colour
// (§13.2). One drawing is the brown wall, the gold goal and the pale path.
//
// Four cells, and a hexagon is symmetric under a sixth of a turn, so each is used
// at six rotations: twenty-four appearances from four drawings, which is what
// stops sixty tiles wearing the same crack.
uniform sampler2D face_map : source_color, filter_linear_mipmap;
uniform float face_strength = 0.0;
const float FACE_CELLS = 2.0;
const float FACE_TURN = 1.0471976;   // 60 degrees
// The art is drawn pointy-top, the same way round as the lattice, so there is no
// half-step to make. It is a constant rather than nothing because the next sheet
// may not be — `cut_faces.py` reports which way each one was drawn.
const float FACE_ALIGN = 0.0;

// Where the silhouette is drawn, and how much of the rim it takes.
const float OUTLINE_AT = 1.0;
const float OUTLINE_W = 0.05;

// The seam between the raised rim and the inset face, and how much lighter the
// face sits. Small — this is a plate set into a border, not a second tile.
const float PLATE_AT = 0.76;
const float PLATE_W = 0.022;
const float PLATE_LIFT = 1.06;

// §14.1's candidate breathing, as a period in seconds — and **zero when it must
// not run at all**, which is what §14.5 asks for: a loop under Reduce Motion does
// not go faster, it stops, and the candidate holds the bright end of its stroke.
// One uniform rather than a period plus a flag, so the two cannot disagree.
uniform float breathe_seconds = 0.0;

// §14.1's flow pulse: a bright band travelling from the start along the path to
// the cell that was just joined, 300 ms. It rides the depth ratio each instance
// already carries, so the band crosses a tile and the stroke lying on it at the
// same instant rather than needing two clocks. Negative means no pulse is running.
const float FLOW_WIDTH = 0.16;
const float FLOW_GAIN = 0.5;

uniform float flow_head = -1.0;

// §14.1's board ripple: a radial brightness wave leaving a goal, each cell lit
// `RIPPLE_PER_CELL` seconds later than the one inside it. `ripple_time` is seconds
// since the wave left, negative when none is running; the per-instance distance
// travels in the custom data's last free channel.
const float RIPPLE_WINDOW = 0.20;
const float RIPPLE_GAIN = 0.55;

uniform float ripple_time = -1.0;
uniform float ripple_step = 0.028;

// §14.1's dead-state desaturation: the board drops to 70% saturation over 400 ms.
// Applied last, over whatever else the shader has decided, so nothing on a dead
// board keeps its colour while the rest of it loses one.
uniform float saturation = 1.0;

vec3 drain(vec3 c) {
	// Rec. 601 luma, the same weighting §21's greyscale checks read the board by.
	return mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
}


varying vec3 tint;
varying float cursor;
varying flat float kind;
varying flat float depth_along;
varying flat float ripple_distance;
varying vec3 world;
varying flat float tile_width;
varying flat vec3 tile_origin;

void vertex() {
	tint = COLOR.rgb;
	cursor = INSTANCE_CUSTOM.g;
	kind = INSTANCE_CUSTOM.r;
	depth_along = INSTANCE_CUSTOM.b;
	ripple_distance = INSTANCE_CUSTOM.a;
	// Board space, not view space: the hatch is painted on the tile, so it turns
	// with the board instead of swimming across it as the camera yaws.
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	tile_width = length(MODEL_MATRIX[0].xyz);
	// Where this tile stands. The grain is keyed off it, so every instance gets its
	// own piece of stone without a per-instance channel to carry it.
	tile_origin = MODEL_MATRIX[3].xyz;
}

void fragment() {
	// The cursor's tile lifts out of the board by its own light rather than by a
	// second colour. UV.x is 0 at the centre of the top face and 1 at the rim, so
	// the glow gathers at the edge where the outline used to be.
	vec3 glow = tint * cursor * mix(0.15, 0.6, UV.x);
	// `NORMAL` is in view space; the board's up is a world direction.
	float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);

	vec3 base = tint;
	if (grain_strength > 0.0) {
		// Tile-local, then turned and offset by the tile's own hash, so no two
		// neighbours show the same piece of the map at the same angle.
		vec2 local = (world.xz - tile_origin.xz) / (tile_width * GRAIN_SCALE);
		vec2 h = grain_hash(tile_origin.xz);
		float angle = h.x * GRAIN_ROTATION;
		vec2 turned = vec2(
			local.x * cos(angle) - local.y * sin(angle),
			local.x * sin(angle) + local.y * cos(angle));
		// Doubled so 0.5 is neutral: below it darkens, above it lightens.
		float g = texture(grain_map, turned + h * 8.0).r * 2.0;
		base *= mix(1.0, g, grain_strength);
	}
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

	// The drawn face, when the build has one. It replaces the computed outline and
	// plate below rather than joining them — two rims on one tile, one ruled and one
	// drawn, is worse than either.
	float drawn = 0.0;
	if (face_strength > 0.0 && up > 0.35) {
		vec2 h = grain_hash(tile_origin.xz);
		float cell = floor(h.x * FACE_CELLS * FACE_CELLS);
		float angle = FACE_ALIGN + floor(h.y * 6.0) * FACE_TURN;
		vec2 local = (world.xz - tile_origin.xz) / tile_width;
		vec2 turned = vec2(
			local.x * cos(angle) - local.y * sin(angle),
			local.x * sin(angle) + local.y * cos(angle));
		// Into the cell, held a hair inside it so a mip cannot fetch its neighbour.
		vec2 f = clamp(turned * 0.5 + 0.5, 0.004, 0.996);
		vec2 at = (vec2(mod(cell, FACE_CELLS), floor(cell / FACE_CELLS)) + f) / FACE_CELLS;
		float v = texture(face_map, at).r * 2.0;
		drawn = smoothstep(0.35, 0.75, up) * face_strength;
		base *= mix(1.0, v, drawn);
	}

	// The plate and its outline, on the face only: a side is already dark and is
	// separated from its neighbour by the gap between prisms, so an outline there
	// would be ink on ink. Drawn after the hatch so a wall is outlined too rather
	// than having its outline hatched over.
	if (up > 0.35 && drawn <= 0.0) {
		float face = smoothstep(0.35, 0.75, up);
		// Inside the seam the face is lifted a little, which is what makes the rim
		// around it read as standing proud rather than as a drawn ring.
		base *= mix(1.0, PLATE_LIFT, face * (1.0 - smoothstep(
			PLATE_AT - PLATE_W, PLATE_AT + PLATE_W, UV.x)));
		float seam = 1.0 - smoothstep(0.0, PLATE_W, abs(UV.x - PLATE_AT));
		float rim = smoothstep(OUTLINE_AT - OUTLINE_W, OUTLINE_AT, UV.x);
		base = mix(base, tile_ink.rgb, clamp(max(seam * 0.55, rim), 0.0, 1.0) * face);
	}

	// The travelling band of §14.1, on the cells the path actually runs through.
	int k = int(kind + 0.5);
	if (flow_head >= 0.0 && (k == KIND_PATH || k == KIND_START)) {
		float band = 1.0 - smoothstep(0.0, FLOW_WIDTH, abs(depth_along - flow_head));
		base += tint * band * FLOW_GAIN;
	}

	// The wave, on every cell rather than only the path: §14.1 calls it a board
	// ripple, and a board that did not answer would leave the goal shouting alone.
	if (ripple_time >= 0.0) {
		float local = ripple_time - ripple_distance * ripple_step;
		if (local > 0.0 && local < RIPPLE_WINDOW) {
			float wave = sin(local / RIPPLE_WINDOW * PI);
			base += tint * wave * RIPPLE_GAIN;
		}
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
		EMISSION = drain(face + glow);
	} else {
		ALBEDO = drain(face);
		ROUGHNESS = 0.55;
		SPECULAR = 0.25;
		EMISSION = drain(glow);
	}
}
