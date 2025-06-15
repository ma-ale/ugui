#version 450

layout(set = 3, binding = 0) uniform Viewport {
    ivec2 view;
};

layout(location = 0) in vec2 uv;
layout(location = 0) out vec4 fragColor;

layout(set = 2, binding = 0) uniform sampler2D tx;

void main()
{
    ivec2 ts = textureSize(tx, 0);
    vec2 fts = vec2(ts);
    vec2 real_uv = uv / fts;
    fragColor = texture(tx, real_uv);
}