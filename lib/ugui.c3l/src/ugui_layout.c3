module ugui;

import std::math;
import std::io;

enum LayoutDirection {
	ROW,
	COLUMN,
}

enum Anchor {
	TOP_LEFT,
	LEFT,
	BOTTOM_LEFT,
	BOTTOM,
	BOTTOM_RIGHT,
	RIGHT,
	TOP_RIGHT,
	TOP,
	CENTER
}

struct Layout {
	Size w, h;
	struct children {
		Size w, h;
	}
	ushort grow_children;
	short occupied;
	struct origin {
		short x, y;
	}
	LayoutDirection dir;
	Anchor anchor;
	// FIXME: all this cruft with margin border and padding could be resolved by simply providing
	//        a "Rect content_offset" that represents the combined effect of all three above 
	Rect margin, border, padding;
}

// Total width of a layout element, complete with margin, border and padding
macro Size Layout.total_width(&el)
{
	Rect min = (Rect){.w = el.w.min, .h = el.h.min}.expand(el.margin).expand(el.border).expand(el.padding);
	Rect max = (Rect){.w = el.w.max, .h = el.h.max}.expand(el.margin).expand(el.border).expand(el.padding);
	return {.min = min.w, .max = max.w};
}

// Total height of a layout element, complete with margin, border and padding
macro Size Layout.total_height(&el)
{
	Rect min = (Rect){.w = el.w.min, .h = el.h.min}.expand(el.margin).expand(el.border).expand(el.padding);
	Rect max = (Rect){.w = el.w.max, .h = el.h.max}.expand(el.margin).expand(el.border).expand(el.padding);
	return {.min = min.h, .max = max.h};
}

// The content space of the element
macro Point Elem.content_space(&e)
{
	return {
		.x = e.bounds.w - e.layout.border.x - e.layout.border.w - e.layout.padding.x - e.layout.padding.w,
		.y = e.bounds.h - e.layout.border.y - e.layout.border.h - e.layout.padding.y - e.layout.padding.h,
	};
 }

// Update the parent element's grow children counter 
fn void update_parent_grow(Elem* child, Elem* parent)
{
	switch (parent.layout.dir) {
	case ROW:
		if (child.layout.w.@is_grow()) parent.layout.grow_children++;
	case COLUMN:
		if (child.layout.h.@is_grow()) parent.layout.grow_children++;
	}
}

// Update the parent element's children size
fn void update_parent_size(Elem* child, Elem* parent)
{
	Layout* cl = &child.layout;
	Layout* pl = &parent.layout; 

	switch (pl.dir) {
	case ROW: // on rows grow the ch width by the child width and only grow ch height if it exceeds
		pl.children.w += cl.total_width();
		pl.children.h = pl.children.h.comb_max(cl.total_height());
	case COLUMN: // do the opposite on column
		pl.children.w = pl.children.w.comb_max(cl.total_width());
		pl.children.h += cl.total_height();
	}
}

fn void update_children_bounds(Elem* child, Elem* parent)
{
	parent.children_bounds = containing_rect(child.bounds, parent.bounds);
}

macro Rect Elem.content_bounds(&elem, style) => elem.bounds.pad(style.border).pad(style.padding);

/*
macro Rect Elem.get_view(&elem)
{
	Rect off;
	if (elem.div.scroll_x.enabled && elem.div.scroll_x.on) {
		off.x = (short)((float)(elem.div.pcb.w - elem.bounds.w) * elem.div.scroll_x.value);
		off.w = -elem.div.scroll_size;
	}
	if (elem.div.scroll_y.enabled && elem.div.scroll_y.on) {
		off.y = (short)((float)(elem.div.pcb.h - elem.bounds.h) * elem.div.scroll_y.value);
		off.h = -elem.div.scroll_size;
	}
	return elem.bounds.add(off);
}

macro Point Elem.get_view_off(&elem)
{
	return elem.get_view().sub(elem.bounds).position();
}
*/

// Assign the width and height of an element in the directions that it doesn't need to grow
fn void resolve_dimensions(Elem* e, Elem* p)
{
	// The element's border and paddign total width and height
	Point m_tot = {.x = e.layout.margin.x + e.layout.margin.w, .y = e.layout.margin.y + e.layout.margin.h};
	Point b_tot = {.x = e.layout.border.x + e.layout.border.w, .y = e.layout.border.y + e.layout.border.h};
	Point p_tot = {.x = e.layout.padding.x + e.layout.padding.w, .y = e.layout.padding.y + e.layout.padding.h};

	// ASSIGN WIDTH
	switch {
	case e.layout.w.@is_exact():
		// if width is exact then assign it to the bounds and add border and paddign
		e.bounds.w = e.layout.w.min + b_tot.x + p_tot.x;
	case e.layout.w.@is_grow():
		// done in another pass
		break;
	case e.layout.w.@is_fit(): // fit the element's children
		Size elem_width = e.layout.w; // the element's content width
		Size children_width = e.layout.children.w; // element children (content) width
		Size combined = elem_width.combine(children_width);

		if (combined.min <= combined.max) { // OK!
			// the final element width is the content width plus padding and border
			e.bounds.w = min(elem_width.max, children_width.max) + b_tot.x + p_tot.x;
		} else {
			unreachable("Cannot fit children width: min:%d max:%d", combined.min, combined.max);
		}
		/*
		Size w = e.needed_width().combine(e.layout.children.w);
		if (w.max >= w.min) { // OK!
			e.bounds.w = w.min;
		} else {
			println(e.needed_width(), " ", e.needed_height());
			println(e.layout.children.w, " ", e.layout.children.h);
			unreachable("Cannot fit children width: min:%d max:%d", w.min, w.max);
		}
		*/
	default: unreachable("width is not exact, grow or fit");
	}

	// ASSIGN HEIGHT
	switch {
	case e.layout.h.@is_exact():
		// if width is exact then assign it to the bounds and add border and paddign
		e.bounds.h = e.layout.h.min + b_tot.y + p_tot.y;
	case e.layout.h.@is_grow():
		break;
		// done in another pass
	case e.layout.h.@is_fit(): // fit the element's children
		Size elem_height = e.layout.h; // the element's content width
		Size children_height = e.layout.children.h; // element children (content) width
		Size combined = elem_height.combine(children_height);

		if (combined.min <= combined.max) { // OK!
			// the final element width is the content width plus padding and border
			e.bounds.h = min(elem_height.max, children_height.max) + b_tot.y + p_tot.y;
		} else {
			unreachable("Cannot fit children height: min:%d max:%d", combined.min, combined.max);
		}
		/*
		Size h = e.needed_height().combine(e.layout.children.h);
		if (h.max >= h.min) { // OK!
			e.bounds.h = h.max;
		} else {
			unreachable("Cannot fit children height: min:%d max:%d", h.min, h.max);
		}
		*/
	default: unreachable("width is not exact, grow or fit");
	}

	// the occupied space must account for the element's margin as well
	switch (p.layout.dir) {
	case ROW:
		if (!e.layout.w.@is_grow()) p.layout.occupied += e.bounds.w + m_tot.x;
	case COLUMN:
		if (!e.layout.h.@is_grow()) p.layout.occupied += e.bounds.h + m_tot.y;
	}
}

fn void resolve_grow_elements(Elem* e, Elem* p)
{
	Point m_tot = {.x = e.layout.margin.x + e.layout.margin.w, .y = e.layout.margin.y + e.layout.margin.h};
	Point b_tot = {.x = e.layout.border.x + e.layout.border.w, .y = e.layout.border.y + e.layout.border.h};
	Point p_tot = {.x = e.layout.padding.x + e.layout.padding.w, .y = e.layout.padding.y + e.layout.padding.h};

	// WIDTH
	if (e.layout.w.@is_grow()) {
		if (p.layout.dir == ROW) { // grow along the axis, divide the parent size
			short slot = (short)((p.content_space().x - p.layout.occupied) / p.layout.grow_children);
			// the space slot accounts for the total size, while the element bounds does not account 
			// for the margin
			e.bounds.w = slot - m_tot.x;
			p.layout.grow_children--;
			p.layout.occupied += slot;
		} else if (p.layout.dir == COLUMN) { // grow across the layout axis, inherit width of the parent
			e.bounds.w = p.content_space().x - m_tot.x;
		}
	}
	
	// HEIGHT
	if (e.layout.h.@is_grow()) {
		if (p.layout.dir == COLUMN) { // grow along the axis, divide the parent size
			short slot = (short)((p.content_space().y - p.layout.occupied) / p.layout.grow_children);
			e.bounds.h = slot - m_tot.y;
			p.layout.grow_children--;
			p.layout.occupied += slot;
		} else if (p.layout.dir == ROW) { // grow across the layout axis, inherit width of the parent
			e.bounds.h = p.content_space().y - m_tot.y;
		}
	}
}

fn void resolve_placement(Elem* c, Elem* p)
{
	Layout* pl = &p.layout;
	Layout* cl = &c.layout;

	Point off = {
		.x = p.bounds.x + pl.origin.x + cl.margin.x,
		.y = p.bounds.y + pl.origin.y + cl.margin.x,
	};

	switch (pl.anchor) {
	case TOP_LEFT:
		c.bounds.x = off.x;
		c.bounds.y = off.y;
	case LEFT:
		c.bounds.x = off.x;
		c.bounds.y = off.y + p.bounds.h/2;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied/2;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h/2;
		}
	case BOTTOM_LEFT:
		c.bounds.x = off.x;
		c.bounds.y = off.y + p.bounds.h ;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h;
		}
	case BOTTOM:
		c.bounds.x = off.x + p.bounds.w/2;
		c.bounds.y = off.y + p.bounds.h;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied;
			c.bounds.x -= c.bounds.w/2;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h;
			c.bounds.x -= pl.occupied/2;
		}
	case BOTTOM_RIGHT:
		c.bounds.x = off.x + p.bounds.w;
		c.bounds.y = off.y + p.bounds.h;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied;
			c.bounds.x -= c.bounds.w;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h;
			c.bounds.x -= pl.occupied;
		}
	case RIGHT:
		c.bounds.x = off.x + p.bounds.w;
		c.bounds.y = off.y + p.bounds.h/2;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied/2;
			c.bounds.x -= c.bounds.w;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h/2;
			c.bounds.x -= pl.occupied;
		}
	case TOP_RIGHT:
		c.bounds.x = off.x + p.bounds.w;
		c.bounds.y = off.y;
		if (pl.dir == COLUMN) {
			c.bounds.x -= c.bounds.w;
		} else if (pl.dir == ROW) {
			c.bounds.x -= pl.occupied;
		}
	case TOP:
		c.bounds.x = off.x + p.bounds.w/2;
		c.bounds.y = off.y;
		if (pl.dir == COLUMN) {
			c.bounds.x -= c.bounds.w/2;
		} else if (pl.dir == ROW) {
			c.bounds.x -= pl.occupied/2;
		}
	case CENTER:
		c.bounds.x = off.x + p.bounds.w/2;
		c.bounds.y = off.y + p.bounds.h/2;
		if (pl.dir == COLUMN) {
			c.bounds.x -= c.bounds.w/2;
			c.bounds.y -= pl.occupied/2;
		} else if (pl.dir == ROW) {
			c.bounds.x -= pl.occupied/2;
			c.bounds.y -= c.bounds.h/2;
		}
		break;
	}

	switch (pl.dir) {
	case ROW:
		pl.origin.x += c.bounds.w + cl.margin.x + cl.margin.w;
	case COLUMN:
		pl.origin.y += c.bounds.h + cl.margin.x + cl.margin.w;
	default: unreachable("unknown layout direction");
	}
	
	//sprintln("origin: ", p.layout.origin, " bounds: ", c.bounds);
}

fn void Ctx.layout_element_tree(&ctx)
{
	isz cursor = -1;
	isz current = ctx.tree.level_order_it(0, &cursor)!!;
	for (; current >= 0; current = ctx.tree.level_order_it(0, &cursor)!!) {
		Elem* p = ctx.find_elem(ctx.tree.get(current))!!;
		// offset the origin by the margin
		p.layout.origin.x = p.layout.border.x + p.layout.padding.x;
		p.layout.origin.y = p.layout.border.y + p.layout.padding.y;

		// RESOLVE KNOWN DIMENSIONS
		isz ch_cur = 0;
		isz ch = ctx.tree.children_it(current, &ch_cur)!!;
		for (; ch >= 0; ch = ctx.tree.children_it(current, &ch_cur)!!) {
			Elem* c = ctx.find_elem(ctx.tree.get(ch))!!;
			if (ctx.tree.is_root(ch)!!) {
				resolve_dimensions(p, &&{});
			} else {
				resolve_dimensions(c, p);
			}
		}

		// RESOLVE GROW CHILDREN
		ch_cur = 0;
		ch = ctx.tree.children_it(current, &ch_cur)!!;
		for (; ch >= 0; ch = ctx.tree.children_it(current, &ch_cur)!!) {
			Elem* c = ctx.find_elem(ctx.tree.get(ch))!!;
			if (ctx.tree.is_root(ch)!!) {
				resolve_grow_elements(p, &&{});
			} else {
				resolve_grow_elements(c, p);
			}
		}
		
		// RESOLVE CHILDREN PLACEMENT
		ch_cur = 0;
		ch = ctx.tree.children_it(current, &ch_cur)!!;
		for (; ch >= 0; ch = ctx.tree.children_it(current, &ch_cur)!!) {
			Elem* c = ctx.find_elem(ctx.tree.get(ch))!!;
			if (ctx.tree.is_root(ch)!!) {
				resolve_placement(p, &&{});
				update_children_bounds(c, p);
			} else {
				resolve_placement(c, p);
				update_children_bounds(c, p);
			}
		}
	}
}
