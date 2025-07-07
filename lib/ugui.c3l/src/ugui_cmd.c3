module ugui;

import std::ascii;
import std::io;

// command type
enum CmdType {
	CMD_RECT,
	CMD_UPDATE_ATLAS,
	CMD_SPRITE,
	CMD_SCISSOR,
}

// command to draw a rect
struct CmdRect {
	Rect rect;
	ushort thickness;
	ushort radius;
	Color color;
}

struct CmdUpdateAtlas {
	Id id;
	char* raw_buffer;
	short width, height, bpp;
}

struct CmdSprite {
	Id texture_id;
	SpriteType type;
	Rect rect;
	Rect texture_rect;
	Color hue;
}

// if rect is zero Rect{0} then reset the scissor
struct CmdScissor {
	Rect rect;
}

// command structure
struct Cmd (Printable) {
	CmdType type;
	int z_index; 
	union {
		CmdRect rect;
		CmdUpdateAtlas update_atlas;
		CmdSprite sprite;
		CmdScissor scissor;
	}
}

fn int Cmd.compare_to(Cmd a, Cmd b)
{
	if (a.z_index == b.z_index) return 0;
	return a.z_index > b.z_index ? 1 : -1;
}

// implement the Printable interface
fn usz? Cmd.to_format(Cmd* cmd, Formatter *f) @dynamic
{
	return f.printf("Cmd{ type: %s, z_index: %d }", cmd.type, cmd.z_index);
}

macro bool cull_rect(Rect rect, Rect clip = {0,0,short.max,short.max})
{
	bool no_area = rect.w <= 0 || rect.h <= 0;
	return no_area || !rect.collides(clip);
}

// FIXME: this whole thing could be done at compile time, maybe
macro Ctx.push_cmd(&ctx, Cmd *cmd, int z_index)
{
	cmd.z_index = z_index;
	Rect rect;
	switch (cmd.type) {
	case CMD_RECT: rect = cmd.rect.rect;
	case CMD_SPRITE: rect = cmd.sprite.rect;
	default: return ctx.cmd_queue.enqueue(cmd);
	}
	if (cull_rect(rect, ctx.div_scissor)) return;
	return ctx.cmd_queue.enqueue(cmd);
}

fn void? Ctx.push_scissor(&ctx, Rect rect, int z_index)
{
	Cmd sc = {
		.type = CMD_SCISSOR,
		.scissor.rect = rect.intersection(ctx.div_scissor),
	};
	ctx.push_cmd(&sc, z_index)!;
}

fn void? Ctx.push_rect(&ctx, Rect rect, int z_index, Style* style)
{
	Rect padding       = style.padding;
	ushort border      = style.border;
	ushort radius      = style.radius;
	Color bg           = style.bg;
	Color border_color = style.secondary;

	if (border != 0) {
		Cmd cmd = {
			.type = CMD_RECT,
			.rect.rect = rect,
			.rect.color = border_color,
			.rect.radius = radius+border,
			.rect.thickness = border,
		};
		ctx.push_cmd(&cmd, z_index)!;
	}

	Cmd cmd = {
		.type = CMD_RECT,
		.rect.rect = {
			.x = rect.x + border + padding.x,
			.y = rect.y + border + padding.y,
			.w = rect.w - (border*2) - (padding.x+padding.w),
			.h = rect.h - (border*2) - (padding.y+padding.h),
		},
		.rect.color = bg,
		.rect.radius = radius,
		.rect.thickness = max(rect.w, rect.h),
	};
	if (cull_rect(cmd.rect.rect, ctx.div_scissor)) return;
	ctx.push_cmd(&cmd, z_index)!;
}

fn void? Ctx.push_sprite(&ctx, Rect bounds, Rect texture, Id texture_id, int z_index, Color hue = 0xffffffffu.to_rgba(), SpriteType type = SPRITE_NORMAL)
{
	Cmd cmd = {
		.type = CMD_SPRITE,
		.sprite.type = type,
		.sprite.rect = bounds,
		.sprite.texture_rect = texture,
		.sprite.texture_id = texture_id,
		.sprite.hue = hue,
	};
	ctx.push_cmd(&cmd, z_index)!;
}

fn void? Ctx.push_string(&ctx, Rect bounds, char[] text, int z_index, Color hue)
{
	if (text.len == 0) {
		return;
	}

	ctx.push_scissor(bounds, z_index)!;

	short baseline = (short)ctx.font.ascender;
	short line_height = (short)ctx.font.ascender - (short)ctx.font.descender;
	short line_gap = (short)ctx.font.linegap;
	Id texture_id = ctx.font.id;  // or ctx.font.atlas.id
	Point orig = {
		.x = bounds.x,
		.y = bounds.y,
	};

	short line_len;
	Codepoint cp;
	usz off, x;
	while (off < text.len && (cp = str_to_codepoint(text[off..], &x)) != 0) {
		off += x;
		Glyph* gp;
		if (!ascii::is_cntrl((char)cp)) {
			gp = ctx.font.get_glyph(cp)!;
			Rect gb = {
				.x = orig.x + line_len + gp.ox,
				.y = orig.y + gp.oy + baseline,
				.w = gp.w,
				.h = gp.h,
			};
			Rect gt = {
				.x = gp.u,
				.y = gp.v,
				.w = gp.w,
				.h = gp.h,
			};
			// push the sprite only if it collides with the bounds
			if (!cull_rect(gb, bounds)) ctx.push_sprite(gb, gt, texture_id, z_index, hue)!;
			line_len += gp.adv;
		} else if (cp == '\n'){
			orig.y += line_height + line_gap;
			line_len = 0;
		} else {
			continue;
		}
	}

	// FIXME: we never get here if an error was thrown before
	ctx.push_scissor({}, z_index)!;
}

fn void? Ctx.push_update_atlas(&ctx, Atlas* atlas)
{
	Cmd up = {
		.type = CMD_UPDATE_ATLAS,
		.update_atlas = {
			.id = atlas.id,
			.raw_buffer = atlas.buffer,
			.width = atlas.width,
			.height = atlas.height,
			.bpp = (ushort)atlas.type.bpp(),
			},
		};
	// update the atlases before everything else
	ctx.push_cmd(&up, -1)!;
}

