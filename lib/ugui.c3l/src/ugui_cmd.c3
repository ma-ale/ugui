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
	usz ret;
	
	ret += f.printf("Cmd{ type: %s, z_index: %d, ", cmd.type, cmd.z_index)!;
	switch (cmd.type) {
	case CMD_RECT:
		ret += f.print("CmdRect")!;
		ret += io::struct_to_format(cmd.rect, f, false)!;
	case CMD_SCISSOR:
		ret += f.print("CmdScissor")!;
		ret += io::struct_to_format(cmd.scissor, f, false)!;
	case CMD_SPRITE:
		ret += f.print("CmdSprite")!;
		ret += io::struct_to_format(cmd.sprite, f, false)!;
	case CMD_UPDATE_ATLAS:
		ret += f.print("CmdUpdateAtlas")!;
		ret += io::struct_to_format(cmd.update_atlas, f, false)!;
	}
	
	ret += f.print("}")!;
	return ret;
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
	if (cull_rect(rect, ctx.div_scissor)) {
//		io::print("NOPE: ");
//		io::print(cmd.rect.rect);
//		io::printn(cmd.z_index);
//		unreachable();
		return;
	}
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

fn void? Ctx.reset_scissor(&ctx, int z_index) => ctx.push_cmd(&&(Cmd){.type=CMD_SCISSOR,.scissor.rect=ctx.div_scissor}, z_index)!;

fn void? Ctx.push_rect(&ctx, Rect rect, int z_index, Style* style)
{
	Rect border        = style.border;
	ushort radius      = style.radius;
	Color bg           = style.bg;
	Color border_color = style.secondary;

	// FIXME: this implies that the border has to be uniform
	if (!border.is_null()) {
		Cmd cmd = {
			.type = CMD_RECT,
			.rect.rect = rect,
			.rect.color = border_color,
			.rect.radius = radius + border.x,
		};
		ctx.push_cmd(&cmd, z_index)!;
	}

	Cmd cmd = {
		.type = CMD_RECT,
		.rect.rect = {
			.x = rect.x + border.x,
			.y = rect.y + border.y,
			.w = rect.w - (border.x+border.w),
			.h = rect.h - (border.y+border.h),
		},
		.rect.color = bg,
		.rect.radius = radius,
	};
	ctx.push_cmd(&cmd, z_index)!;
}

// TODO: accept a Sprite* instead of all this shit
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

