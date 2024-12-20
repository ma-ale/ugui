module ugui;

import std::io;
import std::math;

const short SCROLLBAR_DIM = 5;

// div element
struct ElemDiv {
	Layout layout;
	struct scroll_x {
		bool enabled;
		bool on;
		float value;
	}
	struct scroll_y {
		bool enabled;
		bool on;
		float value;
	}
	Rect children_bounds; // current frame children bounds
	Rect pcb; // previous frame children bounds
	Point origin_r, origin_c;
}

fn void! Ctx.div_begin(&ctx, String label, Rect size, bool scroll_x = false, bool scroll_y = false)
{
	Id id = ctx.gen_id(label)!;

	Elem* parent = ctx.get_parent()!;
	Elem* elem = ctx.get_elem(id)!;
	isz div_node = ctx.tree.add(id, ctx.active_div)!;
	ctx.active_div = div_node;

	bool is_new = elem.flags.is_new;

	if (elem.flags.is_new) {
		elem.type = ETYPE_DIV;
	} else if (elem.type != ETYPE_DIV) {
		return UgError.WRONG_ELEMENT_TYPE?;
	}
	elem.div.scroll_x.enabled = scroll_x;
	elem.div.scroll_y.enabled = scroll_y;

	// 2. layout the element
	elem.bounds = ctx.position_element(parent, size);
	elem.div.children_bounds = elem.bounds;

	// update the ctx scissor
	ctx.div_scissor = elem.bounds;
	ctx.push_scissor(elem.bounds)!;

	// 4. Fill the div fields
	elem.div.origin_c = Point{
		.x = elem.bounds.x,
		.y = elem.bounds.y,
	};
	elem.div.origin_r = elem.div.origin_c;
	elem.div.layout   = parent.div.layout;

	// Add the background to the draw stack
	bool do_border = parent.div.layout == LAYOUT_FLOATING;
	ctx.push_rect(elem.bounds, ctx.style.bgcolor, do_border: do_border)!;

	elem.events = ctx.get_elem_events(elem);

	// TODO: check active
	// TODO: check resizeable
}

fn void! Ctx.div_end(&ctx)
{
	// swap the children bounds
	Elem* parent = ctx.get_parent()!;
	Elem* elem = ctx.get_elem_by_tree_idx(ctx.active_div)!;
	elem.div.pcb = elem.div.children_bounds;

	// FIXME: this causes all elements inside the div to loose focus since the mouse press happens
	//        both inside the element and inside the div bounds
	//elem.events = ctx.get_elem_events(elem);
	
	Rect cb = elem.div.pcb;
	// children bounds bottom-right corner
	Point cbc = {
		.x = cb.x + cb.w,
		.y = cb.y + cb.h,
	};
	// div bounds bottom-right corner
	Point bc = {
		.x = elem.bounds.x + elem.bounds.w,
		.y = elem.bounds.y + elem.bounds.h,
	};

	// set the scrollbar flag, is used in layout
	// horizontal overflow
	elem.div.scroll_x.on = cbc.x > bc.x && elem.div.scroll_x.enabled;
	// vertical overflow
	elem.div.scroll_y.on = cbc.y > bc.y && elem.div.scroll_y.enabled;

	Id hsid = ctx.gen_id("div_scrollbar_horizontal")!;
	Id vsid = ctx.gen_id("div_scrollbar_vertical")!;
	
	short wdim = elem.div.scroll_y.on ? (ctx.focus_id == vsid ? SCROLLBAR_DIM*3 : SCROLLBAR_DIM) : 0;
	short hdim = elem.div.scroll_x.on ? (ctx.focus_id == hsid ? SCROLLBAR_DIM*3 : SCROLLBAR_DIM) : 0;

	if (elem.div.scroll_y.on) {
		Rect vslider = {
			.x = elem.bounds.x + elem.bounds.w - wdim,
			.y = elem.bounds.y,
			.w = wdim,
			.h = elem.bounds.h - hdim,
		};
		Layout prev_l = elem.div.layout;
		elem.div.layout = LAYOUT_ABSOLUTE;
		ctx.slider_ver("div_scrollbar_vertical", vslider, &elem.div.scroll_y.value, max((float)bc.y / cbc.y, (float)0.15))!;
		elem.div.layout = prev_l;
	}

	if (elem.div.scroll_x.on) {
		Rect hslider = {
			.x = elem.bounds.x,
			.y = elem.bounds.y + elem.bounds.h - hdim,
			.w = elem.bounds.w - wdim,
			.h = hdim,
		};
		Layout prev_l = elem.div.layout;
		elem.div.layout = LAYOUT_ABSOLUTE;
		ctx.slider_hor("div_scrollbar_horizontal", hslider, &elem.div.scroll_x.value, max((float)bc.x / cbc.x, (float)0.15))!;
		elem.div.layout = prev_l;
	}

	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
}
