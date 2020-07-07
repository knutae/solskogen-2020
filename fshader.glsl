#version 450
in vec2 C;
out vec3 F;
/*layout (location=0)*/ uniform float W;
/*layout (location=1)*/ uniform float H;

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

float horizontal_plane(vec3 p, float height) {
    return p.y - height;
}

float origin_box(vec3 p, vec3 dimensions, float corner_radius) {
    vec3 a = abs(p);
    return length(max(abs(p) - dimensions, 0.0)) - corner_radius;
}

void closest_material(inout float dist, inout ma mat, float new_dist, ma new_mat) {
    if (new_dist < dist) {
        dist = new_dist;
        mat = new_mat;
    }
}

float repeated_boxes_xz(vec3 p, vec3 dimensions, float corner_radius, float modulo) {
    p.xz = mod(p.xz - 0.5 * modulo, modulo) - 0.5 * modulo;
    return origin_box(p, dimensions, corner_radius);
}

float floor(vec3 p) {
    return min(
        horizontal_plane(p, -1),
        repeated_boxes_xz(vec3(p.x, p.y+2, p.z), vec3(1), 0.1, 5));
}

float capsule_cone(vec3 p, vec3 a, vec3 b, float r1, float r2) {
    vec3 pa = p - a;
    vec3 ba = b - a;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba*h) - mix(r1, r2, h);
}

mat2 rotate(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat2(c,-s,s,c);
}

float tree(vec3 p, out ma mat) {
    p.y += 1;
    float dist = 1e100;
    float thickness = 0.1;
    float length = 1.0;
    vec3 base_color = vec3(0.8, 0.4, 0.2);
    vec3 leaf_color = vec3(0.5, 1.0, 0.5);
    vec3 color = base_color;
    int iterations = 20;
    for (int depth = 0; depth < iterations; depth++) {
        float next_thickness = thickness * 0.8;
        float new_dist = capsule_cone(p, vec3(0), vec3(0, length, 0), thickness, next_thickness);
        if (new_dist < dist) {
            color = mix(base_color, leaf_color, depth / float(iterations-1));
        }
        dist = min(dist, new_dist);
        p.y -= length;
        p.x = abs(p.x);
        p.xy *= rotate(0.5 + .02*depth);
        p.zx *= rotate(0.5 + .1*depth);
        thickness = next_thickness;
        length *= 0.75;
    }
    mat = ma(0.1, 0.9, 0.8, 10, 0, color);
    return dist;
}

float repeated_trees(vec3 p, out ma mat) {
    p.xz = mod(p.xz + vec2(2.5), 5.0) - vec2(2.5);
    return tree(p, mat);
}

float scene(vec3 p, out ma mat) {
    //float dist = origin_sphere(p, 1);
    //float dist = capsule(p, vec3(0), vec3(0,1,0), 0.1);
    float dist = repeated_trees(p, mat);
    closest_material(dist, mat, floor(p), ma(0.1, 0.9, 0, 10, 0.0, vec3(0.8)));
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
    vec3 eye_position = vec3(0, 3, 4);
    vec3 forward = normalize(vec3(0, 0.5, -3) - eye_position);
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

vec3 render_aa(float u, float v) {
    // Antialiasing: render and blend 2x2 points per pixel.
    // That means the distance between points is 1/2 pixel,
    // and the distance from the center (du, dv) is 1/4 pixel.
    // Each pixel size is (2.0 / W, 2.0 / H) since the full area is -1 to 1.
    float du = 2.0 / W / 4.0;
    float dv = 2.0 / H / 4.0;
    vec3 sum =
        render(u - du, v - dv) +
        render(u - du, v + dv) +
        render(u + du, v - dv) +
        render(u + du, v + dv);
    return sum / 4;
}

void main() {
    float u = C.x - 1.0;
    float v = (C.y - 1.0) * H / W;
#if defined(DEBUG)
    F = render(u, v);
#else
    F = render_aa(u, v);
#endif
    // vignette
    float edge = abs(C.x - 1) + abs(C.y - 1);
    F = mix(F, vec3(0), min(1, max(0, edge*0.3 - 0.2)));
}
