#version 450
in vec2 C;
out vec3 F;
layout (location=0) uniform float W;
layout (location=1) uniform float H;

// Shader minifier does not (currently) minimize structs, so use short names.
// Using a one-letter name for the struct itself seems to trigger a bug, so use two.
struct ma {
    float A; // ambient
    float D; // diffuse
    float P; // specular
    float S; // shininess
    float R; // reflection
    vec3 C; // RGB color
};

float DRAW_DISTANCE = 500.0;
float PI = acos(-1);

float origin_sphere(vec3 p, float radius) {
    return length(p) - radius;
}

float wobbly_sphere(vec3 p, float radius, float wobbliness) {
    return length(p) - radius
        + wobbliness * radius * (sin(p.x * 123) + sin(p.y * 456) + sin(p.z * 789));
}

void closest_material(inout float dist, inout ma mat, float new_dist, ma new_mat) {
    if (new_dist < dist) {
        dist = new_dist;
        mat = new_mat;
    }
}

float capsule_cone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
    vec3 pa = p - a;
    vec3 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba*h) - mix(r1, r2, h);
 }

float tree_segment(vec3 p, vec3 a, vec3 b, float r1, float r2, float wobbliness, float wobbles) {
    vec3 pa = p - a;
    vec3 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    float angle = atan(p.x, p.z);
    float r = mix(r1, r2, h);
    return length(pa - ba*h) - r + wobbliness*r*(sin(angle*wobbles) + sin(h*PI*6)/2);
}

mat2 rotate(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat2(c,-s,s,c);
}

float signed_pseudo_random(inout float random_seed) {
    float result = sin(random_seed);
    random_seed = round(mod(random_seed*127, 123453));
    return result;
}

float tree(vec3 p, float random_seed, out ma mat) {
    p.y += 1;
    float sphere_radius = 5;
    float dist = wobbly_sphere(p+vec3(0,sphere_radius,0), sphere_radius, 0.005);
    float thickness = 0.1;
    float length = 0.9 + 0.2 * signed_pseudo_random(random_seed);
    vec3 base_color = vec3(0.8, 0.4, 0.2);
    vec3 leaf_color = vec3(0.5, 1.0, 0.5) * (0.85 + 0.15*signed_pseudo_random(random_seed));
    int iterations = 20;
    p.xz *= rotate(mod(random_seed * 11.111, PI*2));
    float rotate1 = 0.5 + signed_pseudo_random(random_seed) * 0.2;
    float rotate2 = 0.5 + signed_pseudo_random(random_seed) * 0.1;
    float thickness_multiplier = 0.8;
    float length_multiplier = 0.75 + 0.01 * signed_pseudo_random(random_seed);
    vec3 color = vec3(0.3, 0.5 + 0.1 * signed_pseudo_random(random_seed), 0.1);
    for (int depth = 0; depth < iterations; depth++) {
        float next_thickness = thickness * thickness_multiplier;
        float new_dist = tree_segment(p, vec3(0), vec3(0, length, 0), thickness, next_thickness, 0.03/(depth+1), 16);
        if (new_dist < dist) {
            color = mix(base_color, leaf_color, depth / float(iterations-1));
        }
        dist = min(dist, new_dist);
        p.y -= length;
        p.x = abs(p.x);
        p.xy *= rotate(rotate1 + .02*depth);
        p.zx *= rotate(rotate2 + .1*depth);
        thickness = next_thickness;
        length *= length_multiplier;
    }
    mat = ma(0.1, 0.9, 0.8, 10, 0, color);
    return dist;
}

float repeated_trees(vec3 p, float modulo, out ma mat) {
    vec2 modvec = mod(p.xz + vec2(modulo/2), modulo) - vec2(modulo/2);
    vec2 divvec = p.xz - modvec;
    // Each tree position (divvec) is used to initialize randomness for that tree: rounding is important to make it stable
    p.y += 3*sin(round(divvec.x)) + 2*sin(round(divvec.y*0.5));
    float random_seed = round(1234 + 3*round(divvec.x) + 5*round(divvec.y));
    random_seed = round(mod(random_seed*127, 123453));
    p.xz = modvec;
    p.x += 0.2*sin(random_seed);
    p.z += 0.1*sin(random_seed*2+10);
    return tree(p, random_seed, mat);
}

float overlapping_repeated_trees(vec3 p, out ma mat) {
    float modulo = 3;
    float dist = repeated_trees(p, modulo*2, mat);
    ma new_mat;
    float new_dist;
    new_dist = repeated_trees(p + vec3(modulo,0,0), modulo*2, new_mat);
    closest_material(dist, mat, new_dist, new_mat);
    new_dist = repeated_trees(p + vec3(0,0,modulo), modulo*2, new_mat);
    closest_material(dist, mat, new_dist, new_mat);
    new_dist = repeated_trees(p + vec3(modulo,0,modulo), modulo*2, new_mat);
    closest_material(dist, mat, new_dist, new_mat);
    return dist;
}

float ellipsoid(vec3 p, vec3 r) {
    float k0 = length(p/r);
    float k1 = length(p/(r*r));
    return k0*(k0-1)/k1;
}

float feather(vec3 p, float len) {
    return ellipsoid(p, vec3(0.1, len, 0.02));
}

float wings(vec3 p) {
    p.y = abs(p.y);
    float dist = 1e10;
    p.xy *= rotate(0.08);
    p.zy *= rotate(0.03);
    for (int i = 0; i < 8; i++) {
        float fl = 1 - pow(0.1*abs(i-4),2);
        dist = min(dist, feather(vec3(p.x, p.y-fl, p.z), fl));
        p.x += 0.02;
        p.xy *= rotate(-0.04);
        p.zy *= rotate(0.01);
    }
    return dist;
}

float tail(vec3 p) {
    float dist = 1e10;
    p.xy *= rotate(-PI/2 + 0.1);
    p.y += 0.4;
    p.x -= 0.015;
    p.z += 0.1;
    p.zy *= rotate(0.15);
    for (int i = 0; i < 6; i++) {
        float fl = 0.4 - 0.02*abs(i-2.5);
        dist = min(dist, feather(vec3(p.x, p.y-0.5-fl, p.z), fl));
        p.x += 0.005;
        p.xy *= rotate(-0.05);
    }
    return dist;
}

float infinite_cone( vec3 p, float a )
{
    vec2 c = vec2(sin(a), cos(a));
    vec2 q = vec2( length(p.xz), -p.y );
    float d = length(q-c*max(dot(q,c), 0.0));
    return d * ((q.x*c.y-q.y*c.x<0.0)?-1.0:1.0);
}

float body(vec3 p) {
    vec3 q = p;
    q.xy *= rotate(PI/2);
    q.y -= 0.5;
    float head = infinite_cone(q, PI/6);
    float beak = capsule_cone(p, vec3(0.6,0,-0.05), vec3(0.36,0,0.013), 0, 0.05);
    return min(
        max(ellipsoid(p, vec3(0.5,0.2,0.1)), head),
        beak);
}

float bird(vec3 p) {
    //p.y -= 3;
    p += vec3(6,-4.3,7);
    p.yz *= rotate(PI/2 + 0.15);
    p.xy *= rotate(-PI/4 - 0.1);
    return min(wings(p), min(tail(p), body(p)));
}

float scene(vec3 p, out ma mat) {
    //float dist = origin_sphere(p, 1);
    //float dist = capsule(p, vec3(0), vec3(0,1,0), 0.1);
    //float dist = repeated_trees(p, 5, mat);
    float dist = overlapping_repeated_trees(p, mat);
    closest_material(dist, mat, bird(p), ma(0.1, 0.9, 0.1, 10, 0, vec3(0.3)));
    return dist;
}

bool ray_march(inout vec3 p, vec3 direction, out ma material) {
    float total_dist = 0.0;
    for (int i = 0; i < 5000; i++) {
        float dist = scene(p, material);
        if (dist < 0.001) {
            return true;
        }
        total_dist += dist;
        if (total_dist > DRAW_DISTANCE) {
            return false;
        }
        p += direction * dist;
    }
    return false;
}

vec3 estimate_normal(vec3 p) {
    float epsilon = 0.001;
    ma m;
    return normalize(vec3(
        scene(vec3(p.x + epsilon, p.y, p.z), m) - scene(vec3(p.x - epsilon, p.y, p.z), m),
        scene(vec3(p.x, p.y + epsilon, p.z), m) - scene(vec3(p.x, p.y - epsilon, p.z), m),
        scene(vec3(p.x, p.y, p.z + epsilon), m) - scene(vec3(p.x, p.y, p.z - epsilon), m)
    ));
}

vec3 ray_reflection(vec3 direction, vec3 normal) {
    return 2.0 * dot(-direction, normal) * normal + direction;
}

float soft_shadow(vec3 p, vec3 light_direction, float sharpness) {
    ma m;
    p += light_direction * 0.1;
    float total_dist = 0.1;
    float res = 1.0;
    for (int i = 0; i < 20; i++) {
        float dist = scene(p, m);
        if (dist < 0.01) {
            return 0.0;
        }
        total_dist += dist;
        res = min(res, sharpness * dist / total_dist);
        if (total_dist > DRAW_DISTANCE) {
            break;
        }
        p += light_direction * dist;
    }
    return res;
}

const vec3 background_color = vec3(0.7, 0.85, 1.0);

vec3 apply_fog(vec3 color, float total_distance) {
    return mix(color, background_color, 1.0 - exp(-0.01 * total_distance));
}

vec3 phong_lighting(vec3 p, ma mat, vec3 ray_direction) {
    vec3 normal = estimate_normal(p);
    vec3 light_direction = normalize(vec3(-0.3, -1.0, -0.5));
    float shadow = soft_shadow(p, -light_direction, 20.0);
    float diffuse = max(0.0, mat.D * dot(normal, -light_direction)) * shadow;
    vec3 reflection = ray_reflection(ray_direction, normal);
    float specular = pow(max(0.0, mat.P * dot(reflection, -light_direction)), mat.S) * shadow;
    return min(mat.C * (diffuse + mat.A) + vec3(specular), vec3(1.0));
}

vec3 apply_reflections(vec3 color, ma mat, vec3 p, vec3 direction) {
    float reflection = mat.R;
    for (int i = 0; i < 3; i++) {
        if (reflection <= 0.01) {
            break;
        }
        vec3 reflection_color = background_color;
        direction = ray_reflection(direction, estimate_normal(p));
        vec3 start_pos = p;
        p += 0.05 * direction;
        if (ray_march(p, direction, mat)) {
            reflection_color = phong_lighting(p, mat, direction);
            reflection_color = apply_fog(reflection_color, length(p - start_pos));
            color = mix(color, reflection_color, reflection);
            reflection *= mat.R;
        } else {
            color = mix(color, reflection_color, reflection);
            break;
        }
    }
    return color;
}

vec3 render(float u, float v) {
    vec3 eye_position = vec3(0, 4, 4);
    vec3 forward = normalize(vec3(0, 1, -3) - eye_position);
    vec3 up = vec3(0.0, 1.0, 0.0);
    vec3 right = normalize(cross(up, forward));
    up = cross(-right, forward);
    float focal_length = 1.0;
    vec3 start_pos = eye_position + forward * focal_length + right * u + up * v;
    vec3 direction = normalize(start_pos - eye_position);
    vec3 p = start_pos;
    vec3 color = background_color;
    ma mat;
    if (ray_march(p, direction, mat)) {
        color = phong_lighting(p, mat, direction);
        color = apply_reflections(color, mat, p, direction);
        color = apply_fog(color, length(p - start_pos));
    }
    return color;
}

void main() {
    float u = C.x - 1.0;
    float v = (C.y - 1.0) * H / W;
    F = render(u, v);
    // vignette
    float edge = abs(C.x - 1) + abs(C.y - 1);
    F = mix(F, vec3(0), min(1, max(0, edge*0.3 - 0.2)));
}
