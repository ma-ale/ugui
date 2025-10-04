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
}


macro Ctx.@row(&ctx, Anchor anchor = TOP_LEFT, ...; @body())
{
	ctx.@div(@fit(), @fit(), ROW, anchor: anchor) {
		@body();
	}!;
}

macro Ctx.@column(&ctx, Anchor anchor = TOP_LEFT, ...; @body())
{
	ctx.@div(@fit(), @fit(), COLUMN, anchor: anchor) {
		@body();
	}!;
}


// useful macro to start and end a div, capturing the trailing block
macro Ctx.@div(&ctx,
               Size width = @grow, Size height = @grow,
               LayoutDirection dir = ROW,
               Anchor anchor = TOP_LEFT,
               bool absolute = false, Point off = {},
               bool scroll_x = false, bool scroll_y = false,
               ...;
               @body()
              )
{
	ctx.div_begin(width, height, dir, anchor, absolute, off, scroll_x, scroll_y, $vasplat)!;
	@body();
	return ctx.div_end()!;
}

macro Ctx.div_begin(&ctx,
                    Size width = @grow(), Size height = @grow(),
                    LayoutDirection dir = ROW,
                    Anchor anchor = TOP_LEFT,
                    bool absolute = false, Point off = {},
                    bool scroll_x = false, bool scroll_y = false,
                    ...
                   )
{
	return ctx.div_begin_id(@compute_id($vasplat), width, height, dir, anchor, absolute, off, scroll_x, scroll_y);
}

fn void? Ctx.div_begin_id(&ctx,
                          Id id,
                          Size width, Size height,
                          LayoutDirection dir,
                          Anchor anchor,
                          bool absolute, Point off,
                          bool scroll_x, bool scroll_y
                         )
{
	id = ctx.gen_id(id)!;

	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_DIV)!.unpack(&elem, &parent);
	ctx.active_div = elem.tree_idx;

	Style* style = ctx.styles.get_style(@str_hash("div"));

	elem.div.scroll_x.enabled = scroll_x;
	elem.div.scroll_y.enabled = scroll_y;
	if (ctx.input.z_index < elem.z_index) ctx.input.z_index = elem.z_index;
	
	// update layout with correct info
	elem.layout = {
		.w = width,
		.h = height,
		.dir = dir,
		.anchor = anchor,
		.content_offset = style.margin + style.border + style.padding,
		.absolute = absolute,
	};
	if (absolute) {
		elem.layout.origin.x = off.x;
		elem.layout.origin.y = off.y;
	}

	ctx.push_rect(elem.bounds.pad(style.margin), elem.z_index, style)!;

	// update the ctx scissor, it HAS to be after drawing the background
	ctx.div_scissor = elem.bounds.pad(elem.layout.content_offset);
	ctx.push_scissor(elem.bounds.pad(elem.layout.content_offset), elem.z_index)!;

	elem.events = ctx.get_elem_events(elem);

	// TODO: check active
	// TODO: check resizeable
}

fn Id? Ctx.div_end(&ctx)
{
	Elem* elem = ctx.get_active_div()!;
	Style* style = ctx.styles.get_style(@str_hash("div"));
	Rect bounds = elem.bounds.pad(style.margin + style.border);

	// set the scrollbar flag, is used in layout
	Point cbc = elem.children_bounds.bottom_right();
	Point bc = elem.bounds.bottom_right();
	// horizontal overflow
	elem.div.scroll_x.on = cbc.x > bc.x && elem.div.scroll_x.enabled;
	// vertical overflow
	elem.div.scroll_y.on = cbc.y > bc.y && elem.div.scroll_y.enabled;

	Id hsid_raw = @str_hash("div_scrollbar_horizontal");
	Id vsid_raw = @str_hash("div_scrollbar_vertical");
	Id hsid_real = ctx.gen_id(hsid_raw)!;
	Id vsid_real = ctx.gen_id(vsid_raw)!;

	if (elem.div.scroll_y.on) {
		if (ctx.input.events.mouse_scroll && ctx.hover_id == elem.id && !(ctx.get_mod() & KMOD_SHIFT)) {
			elem.div.scroll_y.value += ctx.input.mouse.scroll.y * 0.07f;
			elem.div.scroll_y.value = math::clamp(elem.div.scroll_y.value, 0.0f, 1.0f);
		}
		ctx.scrollbar(vsid_raw, &elem.div.scroll_y.value, max((float)bc.y / cbc.y, (float)0.15))!;
		elem.layout.scroll_offset.y = (short)(elem.div.scroll_y.value*(float)(elem.children_bounds.h-elem.bounds.h));
	} else {
		elem.div.scroll_y.value = 0;
	}


	if (elem.div.scroll_x.on) {
		if (ctx.input.events.mouse_scroll && ctx.hover_id == elem.id) {
			if (ctx.get_mod() & KMOD_SHIFT) { // horizontal scroll with shift
				elem.div.scroll_x.value += ctx.input.mouse.scroll.y * 0.07f;
				elem.div.scroll_x.value = math::clamp(elem.div.scroll_x.value, 0.0f, 1.0f);
			} else {
				elem.div.scroll_x.value += ctx.input.mouse.scroll.x * 0.07f;
				elem.div.scroll_x.value = math::clamp(elem.div.scroll_x.value, 0.0f, 1.0f);
			}
		}
		ctx.scrollbar(vsid_raw, &elem.div.scroll_x.value, max((float)bc.x / cbc.x, (float)0.15), false)!;
		elem.layout.scroll_offset.x = (short)(elem.div.scroll_x.value*(float)(elem.children_bounds.w-elem.bounds.w));
	} else {
		elem.div.scroll_x.value = 0;
	}

	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
	Elem* parent = ctx.get_parent()!;
	ctx.div_scissor = parent.bounds.pad(parent.layout.content_offset);
	ctx.reset_scissor(elem.z_index)!;

	update_parent_size(elem, parent);

	return elem.id;
}

macro bool? Ctx.popup_begin(&ctx, Point pos,
                      Size width, Size height,
                      LayoutDirection dir = ROW, Anchor anchor = TOP_LEFT, 
                      bool scroll_x = false, bool scroll_y = false,
                      ...
                     )
	=> ctx.popup_begin_id(@compute_id($vasplat), pos, width, height, dir, anchor, scroll_x, scroll_y);
fn bool? Ctx.popup_begin_id(&ctx, 
                       Id id, 
                       Point pos, 
                       Size width, Size height,
                       LayoutDirection dir, Anchor anchor, 
                       bool scroll_x, bool scroll_y
                      )
{
	id = ctx.gen_id(id)!;

	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_DIV)!.unpack(&elem, &parent);
	ctx.active_div = elem.tree_idx;

	Style* style = ctx.styles.get_style(@str_hash("popup"));

	elem.div.scroll_x.enabled = scroll_x;
	elem.div.scroll_y.enabled = scroll_y;
	elem.z_index++;
	if (ctx.input.z_index < elem.z_index) ctx.input.z_index = elem.z_index;

	// update layout with correct info
	elem.layout = {
		.w = width,
		.h = height,
		.dir = dir,
		.anchor = anchor,
		.content_offset = style.margin + style.border + style.padding,
		.absolute = true,
		.origin.x = pos.x - parent.bounds.x,
		.origin.y = pos.y - parent.bounds.y,
	};

	ctx.push_rect(elem.bounds.pad(style.margin), elem.z_index, style)!;

	// update the ctx scissor, it HAS to be after drawing the background
	ctx.div_scissor = elem.bounds.pad(elem.layout.content_offset);
	ctx.push_scissor(elem.bounds.pad(elem.layout.content_offset), elem.z_index)!;

	elem.events = ctx.get_elem_events(elem);
	
	// check close condition, mouse release anywhere outside the div bounds
	if ((ctx.mouse_released() & BTN_ANY) && !elem.events.mouse_hover) {
		return false;
	}

	// TODO: check active
	// TODO: check resizeable
	return true;
}
