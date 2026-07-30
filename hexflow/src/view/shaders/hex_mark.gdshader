// The glyphs of the C-18 presentation as camera-facing signed-distance shapes:
// the four cell modifiers of §6 — goal, portal, gate, wild — and the direction
// arrow the rail's tile stack carries. One draw call per multimesh using it (C-23).
//
// Two jobs, one per stage.
//
// **vertex** billboards. The quad is rebuilt every frame around the camera's own
// basis, so a mark is always a screen-aligned square: it never rotates, shears or
// foreshortens as the board yaws, and it is exactly as legible at each of the six
// 60° stops as it is at every angle in between. Doing it here rather than by
// rewriting instance transforms costs no CPU at all and stays correct *during*
// C-21's 260 ms tween, not just at its ends.
//
// **fragment** draws the silhouette. §21 asks for a channel that is not colour;
// [BoardTiles] already spent height on the tile's kind (C-22), so a modifier is
// told apart by its outline: a reticle, two concentric rings, a padlock, a
// five-pointed star. The glyph is ringed in `outline` so the shape
// survives being drawn over a tile of similar luminance under a greyscale or
// high-contrast palette.
//
// Every colour arrives per instance from `palette.gd` (§13.2) or as the `outline`
// uniform — deliberately not one literal colour in here, so §21's palettes stay a
// `.tres` swap.
//
// INSTANCE_CUSTOM:
//   r  mark id (BoardMarks.Mark)
//   g  1.0 when a gate is currently enterable, so its lock opens (§6)
//   b  rotation in radians, for the rail's direction arrows; 0 on the board
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled,
	world_vertex_coords;

const int MARK_GOAL = 0;
const int MARK_PORTAL = 1;
const int MARK_GATE = 2;
const int MARK_WILD = 3;
// Not a cell modifier: the direction on a tile in the rail's stack (§12.3). It
// shares this shader because it is the same problem — a glyph that has to stay
// upright and undistorted while the thing under it is drawn at the board's angle.
const int MARK_ARROW = 4;

// Width of the ring drawn around every glyph, in quad units. Each silhouette
// below stays inside 0.9 so this has somewhere to go.
const float OUTLINE = 0.085;

// §14.1's goal pulse: ring scale 1.0 to 1.08, and a brightness swing standing in
// for its glow until §13.1's bloom pass exists.
const float PULSE_SCALE = 1.08;
const float PULSE_DIM = 0.78;

uniform vec4 outline : source_color;

// §14.1's goal pulse, as a period in seconds, zero when §14.5 has stopped it.
// Same one-uniform trick as the tiles' breathing.
uniform float pulse_seconds = 0.0;

// §14.1's dead-state desaturation: the board drops to 70% saturation over 400 ms.
// Applied last, over whatever else the shader has decided, so nothing on a dead
// board keeps its colour while the rest of it loses one.
uniform float saturation = 1.0;

vec3 drain(vec3 c) {
	// Rec. 601 luma, the same weighting §21's greyscale checks read the board by.
	return mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
}


varying vec2 quad;
varying vec3 tint;
varying flat float mark;
varying flat float open;
varying flat float spin;

float sd_circle(vec2 p, float r) {
	return length(p) - r;
}

float sd_ring(vec2 p, float r, float w) {
	return abs(length(p) - r) - w;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sd_round_box(vec2 p, vec2 b, float r) {
	return sd_box(p, b - vec2(r)) - r;
}

// Upper half of an annulus, with round caps where the legs end — a padlock
// shackle standing on the lock body.
float sd_arc(vec2 p, float r, float w) {
	p.x = abs(p.x);
	if (p.y > 0.0) {
		return abs(length(p) - r) - w;
	}
	return length(p - vec2(r, 0.0)) - w;
}

// Five-pointed star, one point up. iq's construction: fold the plane about the
// two mirror lines of the 5-fold symmetry, then measure one edge.
float sd_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-k1.x, k1.y);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

// The silhouettes. The four modifiers differ in shape before they differ in
// anything else, which is the whole of §21's requirement on them.
float mark_sdf(int id, vec2 p, float lock_open) {
	if (id == MARK_GOAL) {
		// A reticle: ring, solid centre, and four ticks. Ring-and-dot alone is a
		// pair of concentric circles, which is what a portal is — in greyscale the
		// two were told apart only by whether the middle was filled. The ticks make
		// the silhouettes differ outright, which is what §21 actually asks for.
		vec2 a = abs(p);
		float ticks = min(
			sd_box(vec2(a.x - 0.81, a.y), vec2(0.07, 0.055)),
			sd_box(vec2(a.x, a.y - 0.81), vec2(0.055, 0.07))
		);
		return min(min(sd_ring(p, 0.60, 0.11), sd_circle(p, 0.20)), ticks);
	}
	if (id == MARK_PORTAL) {
		// Two concentric rings and an empty middle (§6), so it cannot be read as
		// a goal at a glance or in a monochrome capture.
		return min(sd_ring(p, 0.74, 0.10), sd_ring(p, 0.40, 0.10));
	}
	if (id == MARK_GATE) {
		float body = sd_round_box(p - vec2(0.0, -0.28), vec2(0.52, 0.40), 0.12);
		float keyhole = min(
			sd_circle(p - vec2(0.0, -0.20), 0.13),
			sd_box(p - vec2(0.0, -0.38), vec2(0.05, 0.16))
		);
		body = max(body, -keyhole);
		// Open, the shackle swings clear of the body: the lock opens the moment
		// the gate's condition becomes satisfiable (§6).
		vec2 q = p - vec2(lock_open * 0.30, 0.10 + lock_open * 0.12);
		return min(body, sd_arc(q, 0.30, 0.10));
	}
	if (id == MARK_WILD) {
		return sd_star5(p, 0.86, 0.45);
	}
	// An arrow pointing along +x, which the caller rotates to whichever screen
	// angle that direction currently has on the board.
	float shaft = sd_box(p - vec2(-0.22, 0.0), vec2(0.46, 0.13));
	// The head as the intersection of its base and its two mirrored edges. `q`
	// folds the plane about y = 0, so one edge stands for both.
	vec2 q = vec2(p.x, abs(p.y));
	float edge = dot(q - vec2(0.85, 0.0), normalize(vec2(0.42, 0.6)));
	float head = max(edge, 0.24 - p.x);
	return min(shaft, head);
}

void vertex() {
	quad = UV * 2.0 - 1.0;
	tint = COLOR.rgb;
	mark = INSTANCE_CUSTOM.r;
	open = INSTANCE_CUSTOM.g;
	spin = INSTANCE_CUSTOM.b;
	// The instance transform contributes its origin and its (uniform) scale; its
	// orientation is the camera's, taken fresh here. INV_VIEW_MATRIX's first two
	// columns are screen right and screen up in world space.
	vec3 centre = MODEL_MATRIX[3].xyz;
	float radius = length(MODEL_MATRIX[0].xyz);
	VERTEX = centre
		+ (quad.x * INV_VIEW_MATRIX[0].xyz + quad.y * INV_VIEW_MATRIX[1].xyz) * radius;
}

void fragment() {
	// Rotating the sample point backwards draws the glyph forwards. Every cell
	// modifier passes 0 here; only the rail's direction arrows spin.
	float c = cos(spin);
	float s = sin(spin);
	vec2 p = vec2(quad.x * c + quad.y * s, -quad.x * s + quad.y * c);
	// A goal breathes; nothing else does (§14.1). Dividing the sample point grows
	// the glyph, so the ring scales without the quad having to.
	float glow = 1.0;
	if (int(mark + 0.5) == MARK_GOAL && pulse_seconds > 0.0) {
		float phase = 0.5 + 0.5 * sin(TIME * TAU / pulse_seconds);
		p /= mix(1.0, PULSE_SCALE, phase);
		glow = mix(PULSE_DIM, 1.0, phase);
	}
	float d = mark_sdf(int(mark + 0.5), p, open);
	// Resolution-independent edge, as §13.3 does it for the cell SDF.
	float aa = max(fwidth(d), 0.0005);
	float ink = 1.0 - smoothstep(-aa, aa, d);
	float shell = 1.0 - smoothstep(-aa, aa, d - OUTLINE);
	ALBEDO = drain(mix(outline.rgb, tint * glow, ink));
	ALPHA = shell;
}
