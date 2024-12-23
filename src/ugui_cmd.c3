module ugui;

import std::ascii;

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
	ushort radius;
	Color color;
}

struct CmdUpdateAtlas {
	Id id;
	char* raw_buffer;
	short width, height, bpp;
}

// TODO:
//    1. Add atlases as a data type
//    2. Each atlas has an id
struct CmdSprite {
	Rect rect;
	Rect texture_rect;
	Color hue;
	Id texture_id;
}

// if rect is zero Rect{0} then reset the scissor
struct CmdScissor {
	Rect rect;
}

// command structure
struct Cmd {
	CmdType type;
	union {
		CmdRect rect;
		CmdUpdateAtlas update_atlas;
		CmdSprite sprite;
		CmdScissor scissor;
	}
}

macro bool cull_rect(Rect rect, Rect clip = {0,0,short.max,short.max})
{
	bool no_area = rect.w <= 0 || rect.h <= 0;
	return no_area || !rect.collides(clip);
}

// FIXME: this whole thing could be done at compile time, maybe
macro Ctx.push_cmd(&ctx, Cmd *cmd)
{
	Rect rect;
	switch (cmd.type) {
	case CMD_RECT: rect = cmd.rect.rect;
	case CMD_SPRITE: rect = cmd.sprite.rect;
	default: return ctx.cmd_queue.enqueue(cmd);
	}
	if (cull_rect(rect, ctx.div_scissor)) return;
	return ctx.cmd_queue.enqueue(cmd);
}

// FIXME: is this really the best solution?
// "rect" is the bounding box of the element, which includes the border and the padding (so not just the content)
fn void! Ctx.push_rect(&ctx, Rect rect, Color color, bool do_border = false, bool do_padding = false, bool do_radius = false)
{
	Rect border = ctx.style.border;
	Rect padding = ctx.style.padding;
	ushort radius = ctx.style.radius;
	Color border_color = ctx.style.brcolor;

	if (do_border) {
		Cmd cmd = {
			.type = CMD_RECT,
			.rect.rect = rect,
			.rect.color = border_color,
			.rect.radius = do_radius ? radius : 0,
		};
		ctx.push_cmd(&cmd)!;
	}

	Cmd cmd = {
		.type = CMD_RECT,
		.rect.rect = {
			.x = rect.x + (do_border ? border.x : 0) + (do_padding ? padding.x : 0),
			.y = rect.y + (do_border ? border.y : 0) + (do_padding ? padding.y : 0),
			.w = rect.w - (do_border ? border.x+border.w : 0) - (do_padding ? padding.x+padding.w : 0),
			.h = rect.h - (do_border ? border.y+border.h : 0) - (do_padding ? padding.y+padding.h : 0),
		},
		.rect.color = color,
		.rect.radius = do_radius ? radius : 0,
	};
	if (cull_rect(cmd.rect.rect, ctx.div_scissor)) return;
	ctx.push_cmd(&cmd)!;
}

// TODO: add texture id
fn void! Ctx.push_sprite(&ctx, Rect bounds, Rect texture, Id texture_id, Color hue = uint_to_rgba(0xffffffff))
{
	Cmd cmd = {
		.type = CMD_SPRITE,
		.sprite.rect = bounds,
		.sprite.texture_rect = texture,
		.sprite.texture_id = texture_id,
		.sprite.hue = hue,
	};
	ctx.push_cmd(&cmd)!;
}

fn void! Ctx.push_string(&ctx, Rect bounds, String text, Color hue = uint_to_rgba(0xffffffff))
{
	if (text.len == 0) {
		return;
	}

	ctx.push_scissor(bounds)!;

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
	while ((cp = str_to_codepoint(text[off..], &x)) != 0) {
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
			if (!cull_rect(gb, bounds)) ctx.push_sprite(gb, gt, texture_id, hue)!;
			line_len += gp.adv;
		} else if (cp == '\n'){
			orig.y += line_height + line_gap;
			line_len = 0;
		} else {
			continue;
		}
	}

	// FIXME: we never get here if an error was thrown before
	ctx.push_scissor(Rect{})!;
}

fn void! Ctx.push_update_atlas(&ctx, Atlas* atlas)
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
	ctx.push_cmd(&up)!;
}

fn void! Ctx.push_scissor(&ctx, Rect rect)
{
	Cmd sc = {
		.type = CMD_SCISSOR,
		.scissor.rect = rect.intersection(ctx.div_scissor),
	};
	ctx.push_cmd(&sc)!;
}
