module ugui;

import std::io;
import std::math;

enum DivLayout {
	LAYOUT_ROW,
	LAYOUT_COLUMN,
	LAYOUT_FLOATING,
	LAYOUT_ABSOLUTE,
}

// div element
struct ElemDiv {
	DivLayout layout;
	struct scroll {
		bool can_x;
		bool can_y;
		bool on_x;
		bool on_y;
		float value_x;
		float value_y;
	}
	Rect children_bounds; // current frame children bounds
	Rect pcb; // previous frame children bounds
	Point origin_r, origin_c;
	Color bgcolor;
}

fn void! Ctx.div_begin(&ctx, String label, Rect size, bool scroll_x = false, bool scroll_y = false)
{
	Id id = ctx.gen_id(label)!;

	Elem* parent = ctx.get_parent()!;
	Elem* c_elem = ctx.get_elem(id)!;
	isz div_node = ctx.tree.add(id, ctx.active_div)!;
	ctx.active_div = div_node;

	bool is_new = c_elem.flags.is_new;

	if (c_elem.flags.is_new) {
		c_elem.type = ETYPE_DIV;
	} else if (c_elem.type != ETYPE_DIV) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}
	c_elem.div.scroll.can_x = scroll_x;
	c_elem.div.scroll.can_y = scroll_y;

	// 2. layout the element
	c_elem.bounds = ctx.position_element(parent, size);
	c_elem.div.children_bounds = c_elem.bounds;
	c_elem.div.bgcolor = ctx.style.bgcolor;

	// update the ctx scissor
	ctx.div_scissor = c_elem.bounds;
	ctx.push_scissor(c_elem.bounds)!;

	// 4. Fill the div fields
	c_elem.div.origin_c = Point{
		.x = c_elem.bounds.x,
		.y = c_elem.bounds.y,
	};
	c_elem.div.origin_r = c_elem.div.origin_c;
	c_elem.div.layout   = parent.div.layout;

	// Add the background to the draw stack
	bool do_border = parent.div.layout == LAYOUT_FLOATING;
	ctx.push_rect(c_elem.bounds, c_elem.div.bgcolor, do_border: do_border)!;

	c_elem.events = ctx.get_elem_events(c_elem);

	// TODO: check active
	// TODO: check resizeable

	if (parent.flags.has_focus) {
		if (point_in_rect(ctx.input.mouse.pos, c_elem.bounds)) {
			c_elem.flags.has_focus = true;
		}
	}

}

fn void! Ctx.div_end(&ctx)
{
	// swap the children bounds
	Elem* parent = ctx.get_parent()!;
	Elem* c_elem = ctx.get_elem_by_tree_idx(ctx.active_div)!;
	c_elem.div.pcb = c_elem.div.children_bounds;

	c_elem.events = ctx.get_elem_events(c_elem);
	
	Rect cb = c_elem.div.pcb;
	// children bounds bottom-right corner
	Point cbc = {
		.x = cb.x + cb.w,
		.y = cb.y + cb.h,
	};
	// div bounds bottom-right corner
	Point bc = {
		.x = c_elem.bounds.x + c_elem.bounds.w,
		.y = c_elem.bounds.y + c_elem.bounds.h,
	};


	// set the scrollbar flag, is used in layout
	// vertical overflow
	c_elem.div.scroll.on_y = cbc.y > bc.y && c_elem.div.scroll.can_y;
	// horizontal overflow
	c_elem.div.scroll.on_x = cbc.x > bc.x && c_elem.div.scroll.can_x;

	if (c_elem.div.scroll.on_y) {
		Rect vslider = {
			.x = c_elem.bounds.x + c_elem.bounds.w - 10,
			.y = c_elem.bounds.y,
			.w = 10,
			.h = c_elem.bounds.h,
		};
		DivLayout prev_l = c_elem.div.layout;
		c_elem.div.layout = LAYOUT_ABSOLUTE;
		ctx.slider_ver("div_scrollbar_vertical", vslider, &c_elem.div.scroll.value_y, max((float)bc.y / cbc.y, (float)0.15))!;
		c_elem.div.layout = prev_l;
	}

	if (c_elem.div.scroll.on_x) {
		Rect hslider = {
			.x = c_elem.bounds.x,
			.y = c_elem.bounds.y + c_elem.bounds.h - 10,
			.w = c_elem.bounds.w,
			.h = 10,
		};
		DivLayout prev_l = c_elem.div.layout;
		c_elem.div.layout = LAYOUT_ABSOLUTE;
		ctx.slider_hor("div_scrollbar_horizontal", hslider, &c_elem.div.scroll.value_x, max((float)bc.x / cbc.x, (float)0.15))!;
		c_elem.div.layout = prev_l;
	}

	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
}
