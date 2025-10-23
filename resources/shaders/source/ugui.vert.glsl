#version 450

/* Combined vertex shader to render UGUI commands */

// Viewport size in pixels
layout(set = 1, binding = 0) uniform Viewport {
	ivec2 view;
};

// inputs
layout(location = 0) in ivec2 in_position;
layout(location = 1) in ivec4 in_attr; // quad x,y,w,h
layout(location = 2) in ivec4 in_uv;
layout(location = 3) in uvec4 in_color;
layout(location = 4) in uint  in_type;

// outputs
layout(location = 0) out vec4  out_color;
layout(location = 1) out vec2  out_uv;
layout(location = 2) out vec4  out_quad_size;
layout(location = 3) out float out_radius;
layout(location = 4) out uint  out_type;


void main()
{
	// vertex position
	ivec2 px_pos = in_attr.xy + in_position.xy * in_attr.zw;
	vec2 clip_pos;
	clip_pos.x = float(px_pos.x)*2.0 / view.x - 1.0;
	clip_pos.y = -(float(px_pos.y)*2.0 / view.y - 1.0);
	gl_Position = vec4(clip_pos, 0.0, 1.0);

	// color output
	out_color = vec4(in_color) / 255.0;

	// uv output. only useful if the type is SPRITE
	vec2 px_uv = in_uv.xy + in_position.xy * in_uv.zw;
	out_uv = vec2(px_uv);

	// quad size and radius output, only useful if type is RECT
	out_quad_size = vec4(in_attr);
	out_radius = float(abs(in_uv.x));

	// type output
	out_type = in_type;
}