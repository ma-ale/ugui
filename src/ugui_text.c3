module ugui;

import std::io;

fn void! Ctx.text_unbounded(&ctx, String label, String text)
{
	Id id = label.hash();

	Elem *parent = ctx.get_parent()!;
	Elem *c_elem = ctx.get_elem(id)!;
	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;

	// 1. Fill the element fields
	// this resets the flags
	c_elem.type     = ETYPE_TEXT;

	bool update_atlas;
	// if the element is new or the parent was updated then redo layout
	if (c_elem.flags.is_new || parent.flags.updated) {
		Rect text_size;
		Glyph* gp;

		// FIXME: newlines are not counted
		foreach (c: text) {
			Codepoint cp = (Codepoint)c;
			bool n;
			gp = ctx.font.get_glyph(cp, &n)!;
			text_size.w += gp.w + gp.ox + gp.adv;
			text_size.h += gp.h + gp.oy;
			if (n) { update_atlas = true; }
		}
		
		// 2. Layout
		c_elem.bounds = ctx.position_element(parent, text_size, true);

		// 3. Fill the button specific fields
		c_elem.text.str = text;
	}

	if (update_atlas) {
		// FIXME: atlas here is hardcoded, look at the todo in ugui_data
		Cmd up = {
			.type = CMD_UPDATE_ATLAS,
			.update_atlas = {
				.raw_buffer = ctx.font.atlas[0].buffer,
				.width = ctx.font.atlas[0].width,
				.height = ctx.font.atlas[0].height,
			},
		};
		ctx.cmd_queue.enqueue(&up)!;
	}

	Point orig = {
		.x = c_elem.bounds.x,
		.y = c_elem.bounds.y,
	};
	foreach (c: text) {
		Glyph* gp;
		Codepoint cp = (Codepoint)c;
		gp = ctx.font.get_glyph(cp)!;
		
		Cmd cmd = {
			.type = CMD_SPRITE,
			.sprite.rect = {
				.x = orig.x + gp.ox,
				.y = orig.y + gp.oy,
				.w = gp.w,
				.h = gp.h,
			},
			.sprite.texture_rect = {
				.x = gp.u,
				.y = gp.v,
				.w = gp.w,
				.h = gp.h,
			},
		};
		orig.x += gp.w + gp.ox;
		ctx.cmd_queue.enqueue(&cmd)!;
	}
}
