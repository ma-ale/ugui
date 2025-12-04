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
	ResizeAnchor    resize_anchor;
	ResizeAnchor    resize_now;
	ResizeDirection resized; // the element has been manually resized
	Point           resize_size;
}


macro Ctx.@center(&ctx, LayoutDirection dir = ROW, ...; @body())
{
	return ctx.@div(@grow(), @grow(), dir, CENTER) {
		@body();
	}!;
}

macro Ctx.@row(&ctx, Anchor anchor = TOP_LEFT, ...; @body())
{
	return ctx.@div(@fit(), @fit(), ROW, anchor: anchor) {
		@body();
	}!;
}

macro Ctx.@column(&ctx, Anchor anchor = TOP_LEFT, ...; @body())
{
	return ctx.@div(@fit(), @fit(), COLUMN, anchor: anchor) {
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
               ResizeAnchor resize = {},
               ...;
               @body()
              )
{
	ctx.div_begin(width, height, dir, anchor, absolute, off, scroll_x, scroll_y, resize, $vasplat)!;
	@body();
	return ctx.div_end()!;
}

macro Ctx.div_begin(&ctx,
                    Size width = @grow(), Size height = @grow(),
                    LayoutDirection dir, Anchor anchor,
                    bool absolute, Point off,
                    bool scroll_x, bool scroll_y,
                    ResizeAnchor resize,
                    ...
                   )
{
	return ctx.div_begin_id(@compute_id($vasplat), width, height, dir, anchor, absolute, off, scroll_x, scroll_y, resize);
}

fn void? Ctx.div_begin_id(&ctx,
                          Id id,
                          Size width, Size height,
                          LayoutDirection dir,
                          Anchor anchor,
                          bool absolute, Point off,
                          bool scroll_x, bool scroll_y,
                          ResizeAnchor resize
                         )
{
	id = ctx.gen_id(id)!;

	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_DIV)!.unpack(&elem, &parent);
	ctx.active_div = elem.tree_idx;

	Style* style = ctx.styles.get_style(@str_hash("div"));

	elem.div.scroll_x.enabled = scroll_x;
	elem.div.scroll_y.enabled = scroll_y;
	elem.div.resize_anchor = resize;
	
	// check if the div is resizeable
	bool resized = elem.div.resized && (resize != (ResizeAnchor){});
	if (resize != (ResizeAnchor){}) {
		// if the element was not resized yet then the size is as-specified
		// if the element was resized the size is the same as the last frame
		if (elem.div.resized.x == true) {
			width = @exact(elem.div.resize_size.x);
		}
		if (elem.div.resized.y == true) {
			height = @exact(elem.div.resize_size.y);
		}
	}

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
	ctx.div_scissor = elem.bounds.pad(elem.layout.content_offset).max({0,0,0,0});
	ctx.push_scissor(ctx.div_scissor, elem.z_index)!;

	//elem.events = ctx.get_elem_events(elem);

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
		ctx.scrollbar(hsid_raw, &elem.div.scroll_x.value, max((float)bc.x / cbc.x, (float)0.15), false)!;
		elem.layout.scroll_offset.x = (short)(elem.div.scroll_x.value*(float)(elem.children_bounds.w-elem.bounds.w));
	} else {
		elem.div.scroll_x.value = 0;
	}

	// check resize action
	/*
	*                           top border
	 *        +-------------------------------------------+
	 *        | +---------------------------------------+ |
	 *        | |                                       | |
	 *        | |                                       | |
	 *        | |                                       | |
	 *        | |                                       | |
	 *   left | |                                       | | right
	 * border | |                                       | | border
	 *        | |                                       | |
	 *        | |                                       | |
	 *        | |                                       | |
	 *        | |                                       | |
	 *        | +---------------------------------------+ |
	 *        +-------------------------------------------+
	 *                       bottom border
	 */
	if (elem.div.resize_anchor != (ResizeAnchor){}) {
		Rect b = elem.bounds;
		Rect s = style.border + style.margin + style.padding;
		Rect b_l = {.x = b.x, .y = b.y, .w = s.x, .h = b.h};
		Rect b_r = {.x = b.x+b.w-s.w, .y = b.y, .w = s.w, .h = b.h};
		Rect b_t = {.x = b.x, .y = b.y, .w = b.w, .h = s.y};
		Rect b_b = {.x = b.x, .y = b.y+b.h, .w = b.w, .h = s.h};
		
		Rect content_bounds = elem.bounds.pad(elem.layout.content_offset);
		Point m = ctx.input.mouse.pos;
		if (elem.events.mouse_hover && elem.events.mouse_press) {
			if (elem.div.resize_anchor.right  && m.in_rect(b_r)) elem.div.resize_now.right = true;
			if (elem.div.resize_anchor.left   && m.in_rect(b_l)) elem.div.resize_now.left = true;
			if (elem.div.resize_anchor.top    && m.in_rect(b_t)) elem.div.resize_now.top = true;
			if (elem.div.resize_anchor.bottom && m.in_rect(b_b)) elem.div.resize_now.bottom = true;
		} else if (ctx.is_mouse_released(BTN_ANY)) {
			elem.div.resize_now = {};
		}

		if (elem.div.resize_now.right == true) {
			elem.div.resized.x = true;
			elem.div.resize_size.x = content_bounds.w - (elem.bounds.x + elem.bounds.w - m.x);
		}
		if (elem.div.resize_now.bottom == true) {
			elem.div.resized.y = true;
			elem.div.resize_size.y = content_bounds.h - (elem.bounds.y + elem.bounds.h - m.y);
		}
		if (elem.div.resize_now.left == true) {
			elem.div.resized.x = true;
			elem.div.resize_size.x = content_bounds.w - (elem.bounds.x - m.x);
		}
		if (elem.div.resize_now.top == true) {
			elem.div.resized.y = true;
			elem.div.resize_size.y = content_bounds.h - (elem.bounds.y - m.y);
		}
		
	}

	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
	Elem* parent = ctx.get_parent()!;
	ctx.div_scissor = parent.bounds.pad(parent.layout.content_offset).max({0,0,0,0});
	ctx.reset_scissor(elem.z_index)!;

	update_parent_size(elem, parent);

	return elem.id;
}

<* @param[&inout] state *>
macro Ctx.@popup(&ctx, bool* state,
             Point pos,
             Size width, Size height,
             LayoutDirection dir = ROW, Anchor anchor = TOP_LEFT, 
             bool scroll_x = false, bool scroll_y = false,
             ...; @body())
{
	if (*state) {
		*state = ctx.popup_begin(pos, width, height, dir, anchor, scroll_x, scroll_y)!;
		@body();
		ctx.div_end()!;
	}
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

	// if the position is not the one expected then request a frame-skip to not flash appear in the
	// wrong position for one frame
	if (elem.bounds.position() != pos) {
		ctx.skip_frame = true;
		return true;
	}

	ctx.push_rect(elem.bounds.pad(style.margin), elem.z_index, style)!;

	// update the ctx scissor, it HAS to be after drawing the background
	ctx.div_scissor = elem.bounds.pad(elem.layout.content_offset).max({0,0,0,0});
	ctx.push_scissor(ctx.div_scissor, elem.z_index)!;

	//elem.events = ctx.get_elem_events(elem);
	
	// check close condition, mouse release anywhere outside the div bounds
	if ((ctx.mouse_released() & BTN_ANY) && ctx.input.mouse.pos.outside(elem.bounds)) {
		return false;
	}

	// TODO: check active
	return true;
}
