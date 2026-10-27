shader_type canvas_item;
render_mode unshaded;

// The terrain is a grid of 4x4 world-unit cells (R = material, G = scorch).
// Each cell is shaded as 2x2 art pixels so it matches the sprites' pixel size.
// Materials: 1 dirt, 2 concrete, 3 wood, 4 rock, 5 steel grating, 6 chain-link fence, 7 ice, 8 rubber tarp.

uniform vec2 cells = vec2(1600.0, 135.0);
uniform vec2 cell_offset = vec2(0.0);   // world cell of texel (0,0); keeps patterns stable on debris
uniform vec3 tint = vec3(1.0);
uniform vec3 grass_col : source_color = vec3(0.486, 0.69, 0.259);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

int mat_at(sampler2D tex, ivec2 c) {
	ivec2 sz = ivec2(cells);
	if (c.x < 0 || c.y < 0 || c.x >= sz.x || c.y >= sz.y) {
		return c.y >= sz.y ? 4 : 0;
	}
	return int(texelFetch(tex, c, 0).r * 255.0 + 0.5);
}

void fragment() {
	vec2 cp = UV * cells;
	ivec2 cell = ivec2(floor(cp));
	vec2 sub = fract(cp);
	ivec2 sp = ivec2(floor(sub * 2.0));            // which art pixel inside the cell
	vec2 ap = vec2(cell * 2 + sp) + cell_offset * 2.0;  // world art-pixel coordinate
	int m = mat_at(TEXTURE, cell);
	float n = hash(ap);
	vec3 c;
	if (m == 0) {
		// grass tufts poke up out of the dirt below
		int below = mat_at(TEXTURE, cell + ivec2(0, 1));
		if (below == 1 && sp.y == 1 && mat_at(TEXTURE, cell + ivec2(0, -1)) == 0 && n < 0.45) {
			c = grass_col * (n < 0.2 ? 1.15 : 0.95);
			COLOR = vec4(c * tint, 1.0);
		} else {
			COLOR = vec4(0.0);
		}
	} else if (m == 5) {
		// steel grating: a bright top rail and bottom rail, open slots between the bars
		bool rim = mat_at(TEXTURE, cell + ivec2(0, -1)) != 5 && sp.y == 0;
		bool base = mat_at(TEXTURE, cell + ivec2(0, 1)) != 5 && sp.y == 1;
		if (!rim && !base && mod(ap.x, 3.0) >= 1.0) {
			COLOR = vec4(0.0);
		} else {
			c = rim ? vec3(0.66, 0.7, 0.74) : vec3(0.3, 0.33, 0.37);
			if (n > 0.94) c = vec3(0.55, 0.36, 0.24); // rust
			float scorch = texelFetch(TEXTURE, clamp(cell, ivec2(0), ivec2(cells) - 1), 0).g;
			COLOR = vec4(mix(c, vec3(0.1, 0.07, 0.05), scorch * 0.7) * tint, 1.0);
		}
	} else if (m == 6) {
		// chain-link panel: posts at both edges, a top rail with barbed wire, diamond mesh between
		bool edge_l = mat_at(TEXTURE, cell + ivec2(-1, 0)) != 6 && sp.x == 0;
		bool edge_r = mat_at(TEXTURE, cell + ivec2(1, 0)) != 6 && sp.x == 1;
		bool top = mat_at(TEXTURE, cell + ivec2(0, -1)) != 6;
		bool wire = mod(ap.x + ap.y, 3.0) < 1.0 || mod(ap.x - ap.y, 3.0) < 1.0;
		if (top) {
			c = (sp.y == 0 && mod(ap.x, 2.0) < 1.0) ? vec3(0.42, 0.44, 0.47) : vec3(0.74, 0.77, 0.8);
			COLOR = vec4(c * tint, (sp.y == 0 && mod(ap.x, 2.0) >= 1.0) ? 0.0 : 1.0);
		} else if (edge_l || edge_r) {
			c = vec3(0.5, 0.53, 0.57);
			COLOR = vec4(c * tint, 1.0);
		} else if (wire) {
			c = vec3(0.78, 0.8, 0.83);
			COLOR = vec4(c * tint, 0.9);
		} else {
			COLOR = vec4(0.0);
		}
	} else {
		bool up_e = mat_at(TEXTURE, cell + ivec2(0, -1)) == 0;
		bool up2_e = mat_at(TEXTURE, cell + ivec2(0, -2)) == 0;
		bool dn_e = mat_at(TEXTURE, cell + ivec2(0, 1)) == 0;
		bool lf_e = mat_at(TEXTURE, cell + ivec2(-1, 0)) == 0;
		bool rt_e = mat_at(TEXTURE, cell + ivec2(1, 0)) == 0;
		bool edge = (up_e && sp.y == 0) || (dn_e && sp.y == 1) || (lf_e && sp.x == 0) || (rt_e && sp.x == 1);
		if (m == 1) {
			if (up_e) {
				c = sp.y == 0 ? grass_col * 1.18 : grass_col * 0.86;
			} else if (up2_e && (sp.y == 0 || n < 0.5)) {
				c = grass_col * 0.62;
			} else {
				float band = floor(ap.y / 6.0);
				float h2 = hash(vec2(floor(ap.x / 3.0), band));
				c = vec3(0.53, 0.35, 0.19);
				if (n < 0.12) c = vec3(0.42, 0.27, 0.15);
				else if (n > 0.9) c = vec3(0.62, 0.42, 0.24);
				if (h2 < 0.06) c = vec3(0.66, 0.6, 0.52); // pebbles
			}
		} else if (m == 2) {
			bool mortar_row = mod(ap.y, 6.0) < 1.0;
			float row = floor(ap.y / 6.0);
			bool mortar_col = mod(ap.x + mod(row, 2.0) * 6.0, 12.0) < 1.0;
			c = vec3(0.56, 0.58, 0.61);
			if (mortar_row || mortar_col) c = vec3(0.36, 0.37, 0.41);
			else if (n < 0.1) c = vec3(0.47, 0.49, 0.52);
			if (up_e && sp.y == 0) c = vec3(0.72, 0.74, 0.78);
		} else if (m == 3) {
			bool seam = mod(ap.y, 4.0) < 1.0;
			c = mod(ap.y, 4.0) < 2.0 ? vec3(0.63, 0.44, 0.24) : vec3(0.52, 0.34, 0.18);
			if (seam) c = vec3(0.34, 0.22, 0.12);
			if (mod(ap.x, 9.0) < 1.0 && !seam) c = vec3(0.4, 0.26, 0.13);
			if (n > 0.95) c = vec3(0.7, 0.7, 0.66); // nail heads
		} else if (m == 7) {
			// sheet ice: pale blue, a white glaze on top and diagonal glints
			c = vec3(0.62, 0.82, 0.93);
			if (n < 0.15) c = vec3(0.52, 0.72, 0.86);
			if (mod(ap.x - ap.y, 7.0) < 1.0) c = vec3(0.86, 0.95, 1.0);
			if (up_e && sp.y == 0) c = vec3(0.95, 0.99, 1.0);
		} else if (m == 8) {
			// rubber tarp: black-green with a yellow hazard stripe along the top
			c = vec3(0.16, 0.2, 0.17);
			if (n > 0.9) c = vec3(0.22, 0.27, 0.23);
			if (up_e && sp.y == 0) c = mod(floor(ap.x / 3.0), 2.0) < 1.0 ? vec3(0.95, 0.78, 0.2) : vec3(0.12, 0.12, 0.12);
		} else {
			vec2 q = floor(ap / vec2(5.0, 4.0));
			float h2 = hash(q + vec2(floor(mod(q.y, 2.0)) * 0.5, 0.0));
			c = mix(vec3(0.36, 0.3, 0.25), vec3(0.47, 0.39, 0.32), h2);
			if (mod(ap.x + q.y * 2.0, 5.0) < 1.0 || mod(ap.y, 4.0) < 1.0) c *= 0.72;
			if (up_e && sp.y == 0) c = vec3(0.56, 0.5, 0.42);
		}
		if (edge && !(m == 1 && up_e && sp.y == 0)) c *= 0.55;
		float scorch = texelFetch(TEXTURE, clamp(cell, ivec2(0), ivec2(cells) - 1), 0).g;
		c = mix(c, vec3(0.1, 0.07, 0.05), scorch * 0.7);
		COLOR = vec4(c * tint, 1.0);
	}
}
