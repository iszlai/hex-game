// The light that spills through the edge a placement would cross.
//
// [BoardSeams] used to draw a solid bar on that edge, and a bar is the wrong
// object: it has two hard ends and two hard sides, so at this camera it read as a
// blue chip wedged into the crevice rather than as an opening. What it should look
// like is the tile being lit from that side — brightest against the boundary,
// gone by the middle of the cell.
//
// So the geometry is a flat quad lying on the candidate's own top face with its
// near edge on the boundary, and every hard edge it has is dissolved here:
//
//   v  0 at the boundary, 1 at the far end of the wash — the falloff inward
//   u  0 and 1 at the two ends of the shared edge — the taper along it
//
// Additive and unshaded, because it is light rather than a surface. It takes no
// key light, casts nothing, and writes no depth: it is a wash *on* a tile, and a
// wash that occluded its own tile would be a decal with an outline again.
//
// Colour arrives per instance from `palette.gd` (§13.2) — no literal in here, so
// §21's palettes stay a `.tres` swap.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// How sharply the wash dies away from the boundary. Above 1 it hugs the edge,
// which is what keeps it reading as light coming *through* the seam rather than as
// the whole cell being tinted a second time — the candidate tint already does that
// job and this one must not compete with it.
const float FALLOFF = 2.2;

// How much of each end of the seam is spent softening. The wash runs to the two
// corners of the shared edge at full strength and only feathers within this
// fraction of it — enough to kill the aliased vertical cut a hard end leaves, not
// enough to stop it arriving.
//
// It can afford to: a hexagon *widens* inward from any edge (half-width goes from
// R/2 at the edge to R at the centre), so a wash exactly as wide as the edge it
// starts on stays inside the cell however far in it reaches. The sine taper this
// replaces was solving a spill that geometry had already ruled out, and it cost
// the corners to do it.
const float EDGE_SOFTEN = 0.05;

// §14.1's dead-state desaturation, applied last, exactly as the tiles and the
// ribbon apply it — a dead board must not keep one thing in colour.
uniform float saturation = 1.0;

// §21's flat-board setting (C-24). The wash is already unshaded, so there is
// nothing to switch off; what changes is that a flat board is read at lower
// contrast, and the bleed is pulled back so it cannot bloom over the tint it sits
// beside.
uniform bool flat_board = false;

varying vec3 tint;

vec3 drain(vec3 c) {
	// Rec. 601 luma, the same weighting §21's greyscale checks read the board by.
	return mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
}

void vertex() {
	tint = COLOR.rgb;
}

void fragment() {
	float inward = pow(clamp(1.0 - UV.y, 0.0, 1.0), FALLOFF);
	float along = smoothstep(0.0, EDGE_SOFTEN, UV.x)
		* smoothstep(0.0, EDGE_SOFTEN, 1.0 - UV.x);
	float strength = inward * along * (flat_board ? 0.7 : 1.0);
	ALBEDO = drain(tint) * strength;
	ALPHA = strength;
}
