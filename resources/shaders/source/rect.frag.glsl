#version 450

layout(set = 3, binding = 0) uniform Viewport {
    ivec2 view;
};

layout(location = 0) in vec4 in_color;
layout(location = 1) in vec4 in_quad_size; // x,y, w,h
layout(location = 2) in float in_radius;

layout(location = 0) out vec4 fragColor;

// SDF for a rounded rectangle given the centerpoint, half size and radius, all in pixels
float sdf_rr(vec2 p, vec2 half_size, float radius) {
    vec2 q = abs(p) - half_size + radius;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main()
{
    vec2 centerpoint = in_quad_size.xy + in_quad_size.zw * 0.5;
    vec2 half_size = in_quad_size.zw * 0.5;
    float distance = sdf_rr(vec2(gl_FragCoord) - centerpoint, half_size, in_radius);
    float alpha = 1.0 - smoothstep(0.0, 1.0, distance);

    fragColor = vec4(in_color.rgb, in_color.a * alpha);
}