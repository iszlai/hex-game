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
//   r  BoardLinks.Kind — 0 a lattice connector, 1 a portal tether, 2 a standing one
//   g  how far along the path the bar sits, 0 at the start
//   b  C-31's per-bar seed, so no two strokes wobble alike
//   a  one lattice step as a fraction of the whole path, so `along` is continuous
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Lowered from 0.5 when the crackle landed: a constant emission that bright left
// no headroom above it, so the filaments read as a slightly brighter smooth line
// rather than as arcs. The light the player sees is mostly the crackle now, and
// this is the floor it burns down to.
const float LINK_GLOW = 0.34;

// Matches [BoardTiles]' own flat path, so a ribbon lying on a tile top steps down
// with it rather than floating free of it. See `hex_prism.gdshader` for why.
const float SIDE_SHADE = 0.45;

uniform bool flat_board = false;

// §14.1's dead-state desaturation: the board drops to 70% saturation over 400 ms.
// Applied last, over whatever else the shader has decided, so nothing on a dead
// board keeps its colour while the rest of it loses one.
uniform float saturation = 1.0;

vec3 drain(vec3 c) {
	// Rec. 601 luma, the same weighting §21's greyscale checks read the board by.
	return mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
}


// §14.1's flow pulse: a bright band travelling from the start along the path to
// the cell that was just joined, 300 ms. It rides the depth ratio each instance
// already carries, so the band crosses a tile and the stroke lying on it at the
// same instant rather than needing two clocks. Negative means no pulse is running.
const float FLOW_WIDTH = 0.16;
const float FLOW_GAIN = 0.5;

uniform float flow_head = -1.0;

// §13.1: "a single continuous line of light that grows **and pulses**". Light
// runs the length of the path, start to end, on a loop.
//
// It is a **jolt**, not a swell (C-36). The old wave was a wide band sliding
// along the stroke at a constant rate — symmetric, so light arrived *before* the
// head as well as behind it, and present somewhere on the route at every instant.
// Both of those read as a highlight travelling over a line. A discharge is the
// opposite on each count: nothing ahead of it, a hot tip, a channel behind it
// that drains, and a dark gap afterwards before the next one. The gap is what
// makes it a jolt rather than a rhythm — the eye gets a strike, not a metronome.
//
// §14.1 never gave this a duration, so [BoardLinks.PULSE_SECONDS] chose one and
// says so. Zero stops it dead, which is what §14.5 asks a loop to do under Reduce
// Motion — not to run slowly.
//
// The channel **crackles**: it is broken into flickering filaments by two octaves
// of cheap value noise running against each other, and the whole bolt strobes, so
// what is lit is never the same twice. The *shape* of it is not lit at all — see
// `ZIGZAG` below, which bends the stroke itself.
//
// `EMBER` is the same noise with no travelling head at all, at a fraction of the
// gain — the stroke is never perfectly still between jolts, which is what keeps
// it looking lit from inside rather than painted.
//
// Both tails are measured in **lattice steps**, not in fractions of the route.
// The route's length is whatever the player has built; a tail stated as a
// fraction of it makes a bolt on a twenty-cell path twenty times longer than the
// same bolt on a two-cell one, which is the one thing a physical effect must not
// do. One step is `INSTANCE_CUSTOM.a`, so both stages can convert.
const float JOLT_TRAVEL = 0.30;      // fraction of the period the bolt is in flight
const float JOLT_LEAD = 0.04;        // how far ahead of the tip anything is lit
const float JOLT_TAIL = 3.0;         // steps of draining channel behind the tip
const float JOLT_TIP = 0.03;         // the white-hot head itself
const float JOLT_GAIN = 1.7;
const float JOLT_TIP_GAIN = 3.0;
// The bolt is drawn, not lit: while it is passing, the stroke's own geometry
// kinks into a zigzag and swells, and it relaxes again behind the tip. A thread
// of light wandering *inside* a straight ribbon cannot read as lightning — the
// ribbon is a few pixels across, so whatever the light does in there is a
// shimmer. Bending the bar is the only way the shape reaches the screen.
//
// A triangle wave rather than a sine, because the corners are the whole point of
// a cartoon bolt: a sine is a wave and a saw is a zigzag. Counted **per lattice
// step** rather than over the route, so a two-cell path and a twenty-cell one get
// the same size of tooth instead of the same number of them.
//
// It rides the same `sin(pi*t)` envelope C-31's wobble does, so however far the
// stroke throws itself sideways it still meets its neighbours at the tile centres
// they share — a bolt that broke the route into disconnected pieces would be
// telling the player something false about their path.
const float ZIGZAG = 0.30;           // lateral kick as a fraction of the bar's length
const float ZIGZAG_TEETH = 3.0;      // corners per lattice step
const float ZIGZAG_TAIL = 2.5;       // steps of stroke left jagged behind the tip
const float BOLT_SWELL = 0.7;        // how much wider the stroke is where it is live
// The whole bolt is re-lit 30 times a second at a strength it does not choose,
// which is most of what tells an arc from a lamp: an arc is never the same
// brightness two frames running.
const float STROBE_HZ = 30.0;
const float STROBE_FLOOR = 0.45;
const float EMBER_GAIN = 0.22;

uniform float pulse_seconds = 0.0;


// Value noise off a one-dimensional hash. No texture: a sampler here would be an
// asset to keep, an import to configure and a thing to go missing, for a number
// this shader can work out on its own.
float hash11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

float vnoise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

float crackle(float x, float t) {
	return vnoise(x * 26.0 + t * 9.0) * 0.6
		+ vnoise(x * 61.0 - t * 17.0) * 0.4;
}

// How live the bolt is at [param at], measured along the whole route: nothing
// ahead of the tip beyond a short leader, and an exponential drain behind it.
// Shared by both stages — the vertex shader bends the stroke by it and the
// fragment shader lights it by it, and if the two disagreed the glow would sit
// beside the kink instead of in it.
float bolt_at(float at, float period, float tail_steps, float step_span) {
	float head = fract(TIME / period) / JOLT_TRAVEL;
	float d = at - head;
	float tail = max(tail_steps * step_span, 0.001);
	return (1.0 - smoothstep(0.0, JOLT_LEAD, max(d, 0.0)))
		* exp(min(d, 0.0) / tail);
}

// A triangle wave in -1 … 1, one tooth per unit of [param x].
float zigzag(float x) {
	return abs(fract(x) * 2.0 - 1.0) * 2.0 - 1.0;
}

// The board's ink, shared with the tiles and the modifier marks rather than given
// a token of its own — one outline colour is what makes them look drawn by the
// same hand (C-23, and `board_tiles.gd` says the same thing about `tile_ink`).
//
// A drawn line has an edge. Without one the stroke was a glowing smear lying on
// the board; with it the light sits *inside* something that was drawn, which is
// what C-26 means by ink on a surface that has grain.
//
// Taken across the ribbon's width only, never along its length: the caps at each
// end of a bar butt against the next bar's cap, and inking those would draw a
// dark rung across the stroke at every joint in the route.
const float INK_EDGE = 0.72;   // where the ink starts, as a fraction of half-width

uniform vec3 link_ink = vec3(0.03, 0.04, 0.07);


// C-31: the stroke is drawn rather than ruled.
//
// C-26 makes the game "a hand-drawn scene the player is looking into, not a
// diagram they are reading", and a bar laid dead straight between two cell
// centres is a diagram. So each bar bows and breathes along its own length, off
// two sine octaves seeded per instance.
//
// The envelope is the important part. It is `sin(pi * t)`, which is **zero at
// both ends** — so however far a bar wanders in the middle, it still meets its
// neighbours exactly at the tile centres they share. Without that, every joint in
// the route would show a step, and a line made of disconnected pieces is worse
// than a straight one. The same trick the tether's arc uses (`arc_point`).
// Three octaves, not two. Two gave a lazy S-curve — a line drawn slowly by a
// ruler-shy hand. The third is the *jolt*: short, sharp, and small enough to read
// as the tremor in a drawn stroke rather than as noise.
const float WOBBLE = 0.105;      // lateral bow, as a fraction of the bar's length
const float WAVER = 0.34;        // how much the stroke thickens and thins
const float PI_ = 3.14159265;
const float TAU_ = 6.28318530;

float ink(float t, float seed) {
	return sin(t * 3.1 + seed * TAU_) * 0.54
		+ sin(t * 7.3 + seed * 17.0) * 0.31
		+ sin(t * 16.1 + seed * 41.0) * 0.15;
}

varying vec3 tint;
varying flat float kind;
// Where this fragment sits along the *whole* route, 0 at the start. `depth_along`
// is flat per bar, so on its own a travelling wave would light one bar at a time
// and hop; adding the fraction along the bar makes the coordinate continuous.
varying float along;
// Where this fragment sits across the ribbon, -1 to 1. Captured *before* the
// wobble displaces `VERTEX.z`, or the bow would be read as part of the width and
// the ink would wander from one side of the stroke to the other.
varying float across;
// One lattice step as a fraction of the whole route, carried through so the
// fragment stage can measure the bolt's tail in steps like the vertex stage does.
varying flat float step_span;

void vertex() {
	tint = COLOR.rgb;
	kind = INSTANCE_CUSTOM.r;

	// The instance basis scales x by the span, y by the thickness and z by the
	// width, so a local offset is in units of whichever of those it rides. The
	// bow is wanted in *board* units and has to be divided back out of the width,
	// or a thin ribbon would wander less than a thick one.
	across = VERTEX.z * 2.0;
	float span = length(MODEL_MATRIX[0].xyz);
	float width = max(length(MODEL_MATRIX[2].xyz), 0.0001);
	float t = VERTEX.x + 0.5;
	float envelope = sin(t * PI_);
	float seed = INSTANCE_CUSTOM.b;

	along = INSTANCE_CUSTOM.g + t * INSTANCE_CUSTOM.a;
	step_span = INSTANCE_CUSTOM.a;

	// C-36's zigzag, on the lattice connectors only: a tether is topology, and a
	// dashed arc that threw itself sideways would read as a broken portal rather
	// than as a bolt. Taken before the wobble is added, so what is scaled here is
	// the ribbon's *width* and not C-31's bow — multiplying an offset would swing
	// the whole stroke sideways rather than fatten it.
	float live = 0.0;
	if (pulse_seconds > 0.0 && INSTANCE_CUSTOM.r < 0.5) {
		live = bolt_at(along, pulse_seconds, ZIGZAG_TAIL, INSTANCE_CUSTOM.a);
		// A bolt is heavier than the line it is running through, and this is what
		// stops the zigzag reading as a thin wire knocked out of true.
		VERTEX.z *= 1.0 + live * BOLT_SWELL;
		VERTEX.y *= 1.0 + live * BOLT_SWELL;
	}

	VERTEX.z += ink(t, seed) * envelope * span * WOBBLE / width;
	// And the line is not one weight for its whole run — a drawn one is heavier
	// where the hand pressed. Scaled rather than offset, so it stays symmetric
	// about the surface it is lying on.
	VERTEX.y *= 1.0 + ink(t, seed + 0.37) * envelope * WAVER;

	// Teeth counted in lattice steps: `along / step` is how many cells in this
	// vertex is, whatever length the route happens to be.
	float step_along = along / max(INSTANCE_CUSTOM.a, 0.0001);
	VERTEX.z += zigzag(step_along * ZIGZAG_TEETH + seed) * live * envelope
		* span * ZIGZAG / width;
}

void fragment() {
	// Only a lattice connector glows. §6 calls a tether faint and it describes
	// topology rather than route, so both tether kinds are lit and nothing more —
	// `step` rather than the old `mix`, which went *negative* the moment a third
	// kind existed and would have subtracted light from the board.
	vec3 glow = tint * LINK_GLOW * step(kind, 0.5);
	// A tether is topology rather than route, so the pulse does not run down it.
	if (flow_head >= 0.0 && kind < 0.5) {
		float band = 1.0 - smoothstep(0.0, FLOW_WIDTH, abs(along - flow_head));
		glow += tint * band * FLOW_GAIN;
	}
	// The standing jolt of §13.1, on the same coordinate as the placement band so
	// the two read as the same light rather than as two effects sharing a wire.
	if (pulse_seconds > 0.0 && kind < 0.5) {
		// The tip runs past the end of the route rather than stopping on it: what
		// is left behind it is a draining channel, and cutting the head off at 1.0
		// would leave that channel lit at full strength with nothing pulling it.
		// Carrying on to 1/JOLT_TRAVEL drains the whole stroke well before the
		// period comes round again, which is the dark gap the strike needs.
		//
		// The same `bolt_at` the vertex stage bent the stroke with, on a longer
		// tail: the kink relaxes before the light in it has finished draining, so
		// what the eye follows out of the bolt is a glow rather than a bent bar.
		float channel = bolt_at(along, pulse_seconds, JOLT_TAIL, step_span);
		float d = along - fract(TIME / pulse_seconds) / JOLT_TRAVEL;
		// A narrow window on the noise, so the filaments have dark between them.
		// Widen it and the arc goes back to being a smooth swell.
		float arc = smoothstep(0.38, 0.85, crackle(along, TIME));
		float strobe = mix(STROBE_FLOOR, 1.0, vnoise(floor(TIME * STROBE_HZ) * 1.7));
		glow += tint * channel * (0.10 + arc * 1.9) * JOLT_GAIN * strobe;
		// The tip itself, which is the only part that is not broken up: a discharge
		// has one bright point and a mess behind it.
		glow += tint * (1.0 - smoothstep(0.0, JOLT_TIP, abs(d)))
			* JOLT_TIP_GAIN * strobe;
		// Between jolts the stroke smoulders rather than going flat.
		glow += tint * smoothstep(0.58, 1.0, vnoise(along * 34.0 - TIME * 5.0))
			* EMBER_GAIN;
	}
	// The ink edge. It replaces the stroke's colour rather than darkening it, and
	// takes the glow with it — a lit outline is a halo, which is the opposite of
	// what a drawn edge does.
	float ink = smoothstep(INK_EDGE, 1.0, abs(across));
	vec3 body = mix(tint, link_ink, ink);
	glow *= 1.0 - ink;

	if (flat_board) {
		float up = clamp((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y, 0.0, 1.0);
		ALBEDO = vec3(0.0);
		SPECULAR = 0.0;
		ROUGHNESS = 1.0;
		EMISSION = drain(body * mix(SIDE_SHADE, 1.0, up) + glow);
	} else {
		ALBEDO = drain(body);
		// Smoother and shinier than a tile, so the ribbon separates from the prism
		// it lies on without needing a second colour to do it.
		ROUGHNESS = 0.32;
		SPECULAR = 0.35;
		EMISSION = drain(glow);
	}
}
