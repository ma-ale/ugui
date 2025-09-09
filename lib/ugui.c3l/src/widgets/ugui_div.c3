module ugui;

import std::io;
import std::math;

// div element
struct ElemDiv {
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
}


// useful macro to start and end a div, capturing the trailing block
macro Ctx.@div(&ctx,
               Size width = @grow, Size height = @grow,
               LayoutDirection dir = ROW,
               Anchor anchor = TOP_LEFT,
               bool scroll_x = false, bool scroll_y = false,
               ...; 
               @body()
              )
{
	ctx.div_begin(width, height, dir, anchor, scroll_x, scroll_y, $vasplat)!;
	@body();
	ctx.div_end()!;
}

macro Ctx.div_begin(&ctx,
                    Size width = @grow(), Size height = @grow(),
                    LayoutDirection dir = ROW,
                    Anchor anchor = TOP_LEFT,
                    bool scroll_x = false, bool scroll_y = false,
                    ...
                   )
{
	return ctx.div_begin_id(@compute_id($vasplat), width, height, dir, anchor, scroll_x, scroll_y);
}

fn void? Ctx.div_begin_id(&ctx,
                          Id id,
                          Size width, Size height,
                          LayoutDirection dir,
                          Anchor anchor,
                          bool scroll_x, bool scroll_y
                         )
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

	// update the ctx scissor
	ctx.div_scissor = elem.bounds;
	ctx.push_scissor(elem.bounds, elem.div.z_index)!;

	// update layout with correct info
	elem.layout = {
		.w = width,
		.h = height,
		.dir = dir,
		.anchor = anchor,
		.content_offset = style.margin + style.border + style.padding,
	};
	
	// update parent grow children
	update_parent_grow(elem, parent);

	ctx.push_rect(elem.bounds.pad(style.margin), elem.div.z_index, style)!;

	elem.events = ctx.get_elem_events(elem);

	// TODO: check active
	// TODO: check resizeable
}

fn void? Ctx.div_end(&ctx)
{
	Elem* elem = ctx.get_active_div()!;

/* FIXME: Redo slider functionality
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
*/

	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
	Elem* parent = ctx.get_parent()!;
	ctx.div_scissor = parent.bounds;
	ctx.push_scissor(parent.bounds, elem.div.z_index)!;

	update_parent_size(elem, parent);
}
