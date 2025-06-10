#version 450

layout(location = 0) in vec4 color;
layout(location = 1) in vec2 local_position;
layout(location = 2) in vec2 global_position;
layout(location = 3) in float radius;

layout(location = 0) out vec4 fragColor;

// SDF for a rounded rectangle given the centerpoint, half size and radius, all in pixels
float sdf_rr(vec2 p, vec2 center, vec2 half_size, float radius) {
    // Translate fragment position to rectangle's coordinate system
    p -= center;
    // Adjust for rounded corners: shrink the rectangle by the radius
    vec2 q = abs(p) - half_size + radius;
    // Combine distance components:
    // - max(q, 0.0) handles regions outside the rounded corners
    // - min(max(q.x, q.y), 0.0) handles regions inside the rectangle
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

void main()
{
    // local_position are normalized coordinates in the rectangle, passed from the
    // vertex shader
    /*
     * Window
     * +-----------------------+
     * |              (1,1)    |
     * |     +----------x      |
     * |     |          |      |
     * |     |          |      |
     * |     |   Rect   |      |
     * |     |          |      |
     * |     |          |      |
     * |     x----------+      |
     * |  (-1,-1)              |
     * |                       |
     * +-----------------------+
     */ 

    vec2 dx = dFdx(local_position);
    vec2 dy = dFdy(local_position);
    // Conversion from normalized coordinates to pixels
    vec2 norm_to_px = 1.0 / vec2(length(dx), length(dy));
	
    vec2 centerpoint = global_position - local_position * norm_to_px;
    // the half size of the rectangle is also norm_to_px
    vec2 half_size = 1.0 * norm_to_px;

    float distance = sdf_rr(global_position, centerpoint, half_size, radius);
    float alpha = 1.0 - smoothstep(0.0, 1.0, max(distance, 0.0));

	fragColor = vec4(color.rgb, color.a * alpha);
}