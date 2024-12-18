module ugui;

import std::io;
import std::math;

enum DivLayout {
	LAYOUT_ROW,
	LAYOUT_COLUMN,
	LAYOUT_FLOATING,
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

const Elem DIV_DEFAULTS = {
	.type = ETYPE_DIV,
	.div = {
		.scroll.can_x = false,
		.scroll.can_y = false,
		.scroll.value_x = 0,
		.scroll.value_y = 0,
	},
};

fn void! Ctx.div_begin(&ctx, String label, Rect size, bool scroll_x = false, bool scroll_y = false)
{
	Id id = label.hash();

	Elem* parent = ctx.get_parent()!;
	Elem* c_elem = ctx.get_elem(id)!;
	isz div_node = ctx.tree.add(id, ctx.active_div)!;
	ctx.active_div = div_node;

	bool is_new = c_elem.flags.is_new;

	if (c_elem.flags.is_new) {
		*c_elem = DIV_DEFAULTS;
	} else if (c_elem.type != ETYPE_DIV) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}
	c_elem.div.scroll.can_x = scroll_x;
	c_elem.div.scroll.can_y = scroll_y;

	// 2. layout the element
	c_elem.bounds = ctx.position_element(parent, size);
	c_elem.div.children_bounds = c_elem.bounds;
	c_elem.div.bgcolor = ctx.style.bgcolor;

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

	// FIXME: we cannot use slider elements as scrollbars because of id management
	// scrollbars
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

		short hh = (short)(max((float)bc.y / cbc.y, (float)0.15) * c_elem.bounds.h);
		Rect vhandle = {
			.x = c_elem.bounds.x + c_elem.bounds.w - 10,
			.y = calc_slider(c_elem.bounds.y, c_elem.bounds.h-hh, c_elem.div.scroll.value_y),
			.w = 10,
			.h = hh,
		};

		Point m = ctx.input.mouse.pos;
		if (parent.flags.has_focus && c_elem.events.mouse_hover &&
		    c_elem.events.mouse_hold && point_in_rect(m, vhandle)) {
			vhandle.y = calc_slider(c_elem.bounds.y, c_elem.bounds.h-hh, c_elem.div.scroll.value_y);
			c_elem.div.scroll.value_y = calc_value(c_elem.bounds.y, m.y, c_elem.bounds.h, hh);
			c_elem.flags.updated = true;
		}

		ctx.push_rect(vslider, uint_to_rgba(0x999999ff))!;
		ctx.push_rect(vhandle, uint_to_rgba(0x9999ffff))!;
	}

	if (c_elem.div.scroll.on_x) {
		Rect hslider = {
			.x = c_elem.bounds.x,
			.y = c_elem.bounds.y + c_elem.bounds.h - 10,
			.w = c_elem.bounds.w,
			.h = 10,
		};

		short hw = (short)(max((float)bc.x / cbc.x, (float)0.15) * c_elem.bounds.w);
		Rect hhandle = {
			.x = calc_slider(c_elem.bounds.x, c_elem.bounds.w-hw, c_elem.div.scroll.value_x),
			.y = c_elem.bounds.y + c_elem.bounds.h - 10,
			.w = hw,
			.h = 10,
		};

		Point m = ctx.input.mouse.pos;
		if (parent.flags.has_focus && c_elem.events.mouse_hover &&
		    c_elem.events.mouse_hold && point_in_rect(m, hhandle)) {
			hhandle.x = calc_slider(c_elem.bounds.x, c_elem.bounds.w-hw, c_elem.div.scroll.value_x);
			c_elem.div.scroll.value_x = calc_value(c_elem.bounds.x, m.x, c_elem.bounds.w, hw);
			c_elem.flags.updated = true;
		}

		ctx.push_rect(hslider, uint_to_rgba(0x999999ff))!;
		ctx.push_rect(hhandle, uint_to_rgba(0x9999ffff))!;
	}

	if (parent.flags.has_focus) {
		if (point_in_rect(ctx.input.mouse.pos, c_elem.bounds)) {
			c_elem.flags.has_focus = true;
		}
	}

}

fn void! Ctx.div_end(&ctx)
{
	// swap the children bounds
	Elem* c_elem = ctx.get_elem_by_tree_idx(ctx.active_div)!;
	c_elem.div.pcb = c_elem.div.children_bounds;

	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
}
