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
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

varying vec3 tint;
varying float cursor;

void vertex() {
	tint = COLOR.rgb;
	cursor = INSTANCE_CUSTOM.g;
}

void fragment() {
	ALBEDO = tint;
	ROUGHNESS = 0.55;
	SPECULAR = 0.25;
	// The cursor's tile lifts out of the board by its own light rather than by a
	// second colour. UV.x is 0 at the centre of the top face and 1 at the rim, so
	// the glow gathers at the edge where the outline used to be.
	EMISSION = tint * cursor * mix(0.15, 0.6, UV.x);
}
