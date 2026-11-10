shader_type sky;
// Night over Bethlehem: deep blue sky, twinkling stars, a soft band of the Milky Way, the moon,
// and the great Star shining over the stable.

uniform vec3 star_dir = vec3(-0.75, 0.35, 0.2);
uniform vec3 moon_dir = vec3(0.35, 0.55, -0.75);

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float h = d.y;
	vec3 top = vec3(0.008, 0.012, 0.045);
	vec3 hor = vec3(0.09, 0.1, 0.26);
	vec3 col = mix(hor, top, pow(clamp(h, 0.0, 1.0), 0.45));
	if (h < 0.0) {
		col = mix(hor, vec3(0.015, 0.015, 0.03), clamp(-h * 5.0, 0.0, 1.0));
	}
	if (!AT_CUBEMAP_PASS) {
		// stars that twinkle
		vec3 g = floor(d * 260.0);
		float s = hash(g);
		float tw = 0.55 + 0.45 * sin(TIME * (1.5 + s * 3.0) + s * 60.0);
		float vis = smoothstep(0.0, 0.25, h);
		col += vec3(1.0, 0.95, 0.85) * step(0.9972, s) * tw * vis * 1.6;
		// the Milky Way: a soft cloudy band across the sky
		float band = exp(-pow(dot(d, normalize(vec3(0.4, 0.6, 0.7))) * 4.0, 2.0));
		float cloud = noise(d * 9.0) * 0.6 + noise(d * 23.0) * 0.4;
		col += vec3(0.25, 0.22, 0.35) * band * cloud * vis * 0.35;
	}
	// the moon
	float m = dot(d, normalize(moon_dir));
	col += vec3(0.85, 0.9, 1.0) * (smoothstep(0.9990, 0.9993, m) * 2.5 + pow(max(m, 0.0), 80.0) * 0.12);
	// the Star of Bethlehem: a bright core, a warm halo and four long rays
	vec3 sd = normalize(star_dir);
	float a = max(dot(d, sd), 0.0);
	col += vec3(1.0, 0.92, 0.75) * (pow(a, 4000.0) * 60.0 + pow(a, 300.0) * 2.5 + pow(a, 25.0) * 0.15);
	vec3 up = vec3(0.0, 1.0, 0.0);
	vec3 sx = normalize(cross(sd, up));
	vec3 sy = normalize(cross(sx, sd));
	vec2 q = vec2(dot(d - sd, sx), dot(d - sd, sy));
	float rays = exp(-abs(q.x) * 900.0) * exp(-abs(q.y) * 18.0) + exp(-abs(q.y) * 900.0) * exp(-abs(q.x) * 18.0);
	col += vec3(1.0, 0.95, 0.85) * rays * step(0.0, dot(d, sd)) * 3.0;
	COLOR = col;
}
