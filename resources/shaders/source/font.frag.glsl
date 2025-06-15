#version 450

layout(set = 3, binding = 0) uniform Viewport {
    ivec2 view;
};
layout(set = 2, binding = 0) uniform sampler2D tx;

layout(location = 0) in vec2 uv;
layout(location = 1) in vec4 color;

layout(location = 0) out vec4 fragColor;

void main()
{
    ivec2 ts = textureSize(tx, 0);
    vec2 fts = vec2(ts);
    vec2 real_uv = uv / fts;

    vec4 opacity = texture(tx, real_uv);
    fragColor = vec4(color.rgb, color.a*opacity.r);
}