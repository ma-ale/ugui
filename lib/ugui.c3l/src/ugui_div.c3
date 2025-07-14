module ugui;

import std::io;
import std::math;

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
	ushort scroll_size;
	int z_index;
	Rect children_bounds; // current frame children bounds
	Rect pcb; // previous frame children bounds
	Point origin_r, origin_c;
}

// begin a widget container, or div, the size determines the offset (x,y) width and height.
// if the width or height are zero the width or height are set to the maximum available.
// if the width or height are negative the width or height will be calculated based on the children size
// sort similar to a flexbox, and the minimum size is set by the negative of the width or height
// FIXME: there is a bug if the size.w or size.h == -0
macro Ctx.div_begin(&ctx, Rect size, bool scroll_x = false, bool scroll_y = false, ...)
	=> ctx.div_begin_id(@compute_id($vasplat), size, scroll_x, scroll_y);
fn void? Ctx.div_begin_id(&ctx, Id id, Rect size, bool scroll_x, bool scroll_y)
{
	id = ctx.gen_id(id)!;

	Elem* elem = ctx.get_elem(id, ETYPE_DIV)!;
	Elem* parent = ctx.get_parent()!;
	ctx.active_div = elem.tree_idx;

	Style* style = ctx.styles.get_style(@str_hash("default"));
	Style* slider_style = ctx.styles.get_style(@str_hash("slider"));

	elem.div.scroll_x.enabled = scroll_x;
	elem.div.scroll_y.enabled = scroll_y;
	elem.div.scroll_size = slider_style.size ? slider_style.size : (style.size ? style.size : DEFAULT_STYLE.size);
	elem.div.z_index = parent.div.z_index + 1;

	// 2. layout the element
	Rect wanted_size = {
		.x = size.x,
		.y = size.y,
		.w = size.w < 0 ? max(elem.div.pcb.w, (short)-size.w) : size.w,
		.h = size.h < 0 ? max(elem.div.pcb.h, (short)-size.h) : size.h,
	};
	elem.bounds = ctx.position_element(parent, wanted_size, style);
	elem.div.children_bounds = {};

	// update the ctx scissor
	ctx.div_scissor = elem.bounds;
	ctx.push_scissor(elem.bounds, elem.div.z_index)!;

	// 4. Fill the div fields
	elem.div.origin_c = {
		.x = elem.bounds.x,
		.y = elem.bounds.y
	};
	elem.div.origin_r = elem.div.origin_c;
	elem.div.layout   = parent.div.layout;

	// Add the background to the draw stack
	bool do_border = parent.div.layout == LAYOUT_FLOATING;
	ctx.push_rect(elem.bounds, elem.div.z_index, style)!;

	elem.events = ctx.get_elem_events(elem);

	// TODO: check active
	// TODO: check resizeable
}

fn void? Ctx.div_end(&ctx)
{
	// swap the children bounds
	Elem* elem = ctx.get_active_div()!;
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

	Id hsid_raw = @str_hash("div_scrollbar_horizontal");
	Id vsid_raw = @str_hash("div_scrollbar_vertical");
	Id hsid_real = ctx.gen_id(@str_hash("div_scrollbar_horizontal"))!;
	Id vsid_real = ctx.gen_id(@str_hash("div_scrollbar_vertical"))!;
	short wdim = elem.div.scroll_y.on ? (ctx.focus_id == vsid_real || ctx.is_hovered(ctx.find_elem(vsid_real)) ? elem.div.scroll_size*2 : elem.div.scroll_size) : 0;
	short hdim = elem.div.scroll_x.on ? (ctx.focus_id == hsid_real || ctx.is_hovered(ctx.find_elem(hsid_real)) ? elem.div.scroll_size*2 : elem.div.scroll_size) : 0;

	if (elem.div.scroll_y.on) {
		if (ctx.input.events.mouse_scroll && ctx.hover_id == elem.id) {
			elem.div.scroll_y.value += ctx.input.mouse.scroll.y * 0.07f;
			elem.div.scroll_y.value = math::clamp(elem.div.scroll_y.value, 0.0f, 1.0f);
		}
		Rect vslider = {
			.x = elem.bounds.x + elem.bounds.w - wdim,
			.y = elem.bounds.y,
			.w = wdim,
			.h = elem.bounds.h - hdim,
		};
		Layout prev_l = elem.div.layout;
		elem.div.layout = LAYOUT_ABSOLUTE;
		ctx.slider_ver_id(vsid_raw, vslider, &elem.div.scroll_y.value, max((float)bc.y / cbc.y, (float)0.15))!;
		elem.div.layout = prev_l;
	}

	if (elem.div.scroll_x.on) {
		if (ctx.input.events.mouse_scroll && ctx.hover_id == elem.id) {
			elem.div.scroll_x.value += ctx.input.mouse.scroll.x * 0.07f;
			elem.div.scroll_x.value = math::clamp(elem.div.scroll_x.value, 0.0f, 1.0f);
		}
		Rect hslider = {
			.x = elem.bounds.x,
			.y = elem.bounds.y + elem.bounds.h - hdim,
			.w = elem.bounds.w - wdim,
			.h = hdim,
		};
		Layout prev_l = elem.div.layout;
		elem.div.layout = LAYOUT_ABSOLUTE;
		ctx.slider_hor_id(hsid_raw, hslider, &elem.div.scroll_x.value, max((float)bc.x / cbc.x, (float)0.15))!;
		elem.div.layout = prev_l;
	}

	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
	Elem* parent = ctx.get_parent()!;
	// TODO: reset the scissor back to the parent div
	ctx.div_scissor = parent.bounds;
}
