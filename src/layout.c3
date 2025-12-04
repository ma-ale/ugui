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

bitstruct ResizeDirection : char {
	bool x : 0;
	bool y : 1;
}

bitstruct ResizeAnchor : char {
	bool top    : 0;
	bool bottom : 1;
	bool left   : 2;
	bool right  : 3;
}

struct Layout {
	Size w, h; // size of the CONTENT, does not include margin, border and padding
	struct children { // the children size includes the children's margin/border/pading
		Size w, h;
	}
	TextSize text;
	ushort grow_children;
	short occupied;
	Point origin;
	Point scroll_offset;
	// false: the element is laid out according to the parent
	// true: the element is laid out separate from all other children and the relative position to
	//       the parent is the .origin field
	bool absolute;
	LayoutDirection dir; // the direction the children are laid out
	Anchor anchor;       // how the children are positioned
	Rect content_offset; // combined effect of margin, border and padding
}

// Returns the width and height of a @fit() element based on it's wanted size (min/max)
// and the content size, this function is used to both update the parent's children size and
// give the dimensions of a fit element
// TODO: test and cleanup this function
macro Point Layout.get_dimensions(&el)
{
	Point dim;
	// if the direction is ROW then the text is placed horizontally with the children
	if (el.dir == ROW) {
		Size content_width = el.children.w + el.text.width;
		Size width = el.w.combine(content_width);
		short final_width = width.greater();

		short text_height;
		if (el.text.area != 0) {
			short text_width = (@exact(final_width) - el.children.w).combine(el.text.width).min;
			text_height = @exact((short)(el.text.area / text_width)).combine(el.text.height).min;
		}

		Size content_height = el.children.h.comb_max(@exact(text_height));
		Size height = el.h.combine(content_height);
		short final_height = height.greater();

		dim = {
			.x = final_width + el.content_offset.x + el.content_offset.w,
			.y = final_height + el.content_offset.y + el.content_offset.h,
		};
	} else {
	// if the direction is COLUMN the text and children are one on top of the other
		Size content_width = el.children.w.comb_max(el.text.width);
		Size width = el.w.combine(content_width);
		short final_width = width.greater();

		short text_height;
		if (el.text.area != 0) {
			short text_width = @exact(final_width).combine(el.text.width).min;
			text_height = @exact((short)(el.text.area / text_width)).combine(el.text.height).min;
		}

		Size content_height = el.children.h + @exact(text_height);
		Size height = el.h.combine(content_height);
		short final_height = height.greater();

		dim = {
			.x = final_width + el.content_offset.x + el.content_offset.w,
			.y = final_height + el.content_offset.y + el.content_offset.h,
		};
	}

	// GROSS HACK FOR EXACT DIMENSIONS
	if (el.w.@is_exact()) dim.x = el.w.min + el.content_offset.x + el.content_offset.w;
	if (el.h.@is_exact()) dim.y = el.h.min + el.content_offset.y + el.content_offset.h;

	// GROSS HACK FOR GROW DIMENSIONS
	// FIXME: does this always work?
	if (el.w.@is_grow()) dim.x = 0;
	if (el.h.@is_grow()) dim.y = 0;

	return dim;
}

// The content space of the element
macro Point Elem.content_space(&e)
{
	return {
		.x = (short)max(e.bounds.w - e.layout.content_offset.x - e.layout.content_offset.w, 0),
		.y = (short)max(e.bounds.h - e.layout.content_offset.y - e.layout.content_offset.h, 0),
	};
}

// Update the parent element's children size
fn void update_parent_size(Elem* child, Elem* parent)
{
	Layout* cl = &child.layout;
	Layout* pl = &parent.layout;

	// if the element has absolute position do not update the parent
	if (cl.absolute) return;

	Point child_size = cl.get_dimensions();

	switch (pl.dir) {
	case ROW: // on rows grow the ch width by the child width and only grow ch height if it exceeds
		pl.children.w += @exact(child_size.x);
		pl.children.h = pl.children.h.comb_max(@exact(child_size.y));
		if (child.layout.w.@is_grow()) parent.layout.grow_children++;
	case COLUMN: // do the opposite on column
		pl.children.w = pl.children.w.comb_max(@exact(child_size.x));
		pl.children.h += @exact(child_size.y);
		if (child.layout.h.@is_grow()) parent.layout.grow_children++;
	}
}

macro Rect Elem.content_bounds(&elem) => elem.bounds.pad(elem.layout.content_offset);

// Assign the width and height of an element in the directions that it doesn't need to grow
fn void resolve_dimensions(Elem* e, Elem* p)
{
	Layout* el = &e.layout;
	Layout* pl = &p.layout;

	Point elem_dimensions = el.get_dimensions();
	e.bounds.w = elem_dimensions.x;
	e.bounds.h = elem_dimensions.y;

	// if the element has absolute position do not update the parent
	if (el.absolute) return;

	switch (pl.dir) {
	case ROW:
		if (!el.w.@is_grow()) pl.occupied += e.bounds.w;
	case COLUMN:
		if (!el.h.@is_grow()) pl.occupied += e.bounds.h;
	}
}

fn void resolve_grow_elements(Elem* e, Elem* p)
{
	// WIDTH
	if (e.layout.w.@is_grow()) {
		if (e.layout.absolute) { // absolute children do not need to share space
			e.bounds.w = p.content_space().x;
		} else if (p.layout.dir == ROW) { // grow along the axis, divide the parent size
			short slot = (short)max(((p.content_space().x - p.layout.occupied) / p.layout.grow_children), 0);
			e.bounds.w = slot;
			p.layout.grow_children--;
			p.layout.occupied += slot;
		} else if (p.layout.dir == COLUMN) { // grow across the layout axis, inherit width of the parent
			e.bounds.w = p.content_space().x;
		}
	}

	// HEIGHT
	if (e.layout.h.@is_grow()) {
		if (e.layout.absolute) { // absolute children do not need to share space
			e.bounds.h = p.content_space().y;
		} else if (p.layout.dir == COLUMN) { // grow along the axis, divide the parent size
			short slot = (short)max(((p.content_space().y - p.layout.occupied) / p.layout.grow_children), 0);
			e.bounds.h = slot;
			p.layout.grow_children--;
			p.layout.occupied += slot;
		} else if (p.layout.dir == ROW) { // grow across the layout axis, inherit width of the parent
			e.bounds.h = p.content_space().y;
		}
	}
}

fn void resolve_placement(Elem* c, Elem* p)
{
	Layout* pl = &p.layout;
	Layout* cl = &c.layout;

	Point off = {
		.x = p.bounds.x + pl.origin.x + pl.content_offset.x,
		.y = p.bounds.y + pl.origin.y + pl.content_offset.y,
	};

	// if the element has absolute position assign the origin and do not update the parent
	if (cl.absolute) {
		c.bounds.x = p.bounds.x + pl.content_offset.x + cl.origin.x;
		c.bounds.y = p.bounds.y + pl.content_offset.y + cl.origin.y;
		return;
	}

	switch (pl.anchor) {
	case TOP_LEFT:
		c.bounds.x = off.x;
		c.bounds.y = off.y;
	case LEFT:
		c.bounds.x = off.x;
		c.bounds.y = off.y + p.content_space().y/2;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied/2;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h/2;
		}
	case BOTTOM_LEFT:
		c.bounds.x = off.x;
		c.bounds.y = off.y + p.content_space().y ;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h;
		}
	case BOTTOM:
		c.bounds.x = off.x + p.content_space().x/2;
		c.bounds.y = off.y + p.content_space().y;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied;
			c.bounds.x -= c.bounds.w/2;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h;
			c.bounds.x -= pl.occupied/2;
		}
	case BOTTOM_RIGHT:
		c.bounds.x = off.x + p.content_space().x;
		c.bounds.y = off.y + p.content_space().y;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied;
			c.bounds.x -= c.bounds.w;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h;
			c.bounds.x -= pl.occupied;
		}
	case RIGHT:
		c.bounds.x = off.x + p.content_space().x;
		c.bounds.y = off.y + p.content_space().y/2;
		if (pl.dir == COLUMN) {
			c.bounds.y -= pl.occupied/2;
			c.bounds.x -= c.bounds.w;
		} else if (pl.dir == ROW) {
			c.bounds.y -= c.bounds.h/2;
			c.bounds.x -= pl.occupied;
		}
	case TOP_RIGHT:
		c.bounds.x = off.x + p.content_space().x;
		c.bounds.y = off.y;
		if (pl.dir == COLUMN) {
			c.bounds.x -= c.bounds.w;
		} else if (pl.dir == ROW) {
			c.bounds.x -= pl.occupied;
		}
	case TOP:
		c.bounds.x = off.x + p.content_space().x/2;
		c.bounds.y = off.y;
		if (pl.dir == COLUMN) {
			c.bounds.x -= c.bounds.w/2;
		} else if (pl.dir == ROW) {
			c.bounds.x -= pl.occupied/2;
		}
	case CENTER:
		c.bounds.x = off.x + p.content_space().x/2;
		c.bounds.y = off.y + p.content_space().y/2;
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
		pl.origin.x += c.bounds.w;
	case COLUMN:
		pl.origin.y += c.bounds.h;
	default: unreachable("unknown layout direction");
	}

	// update the parent children_bounds
	// FIXME: this causes scollbars to flicker in/out during resize because the current frames children_bounds are updated
	//        with the previous' frame child bounds. It would be better to implement another pass during layout.
	// FIXME: this long way around to compute the children bounds works and reduces flickering, but it is very ugly 
	Rect ncb = c.children_bounds;
	ncb.x = c.bounds.x;
	ncb.y = c.bounds.y;
	Rect cb = containing_rect(c.bounds, ncb);
	Point o = p.layout.scroll_offset;
	p.children_bounds = containing_rect(cb + o, p.children_bounds);

	// reset the children bounds
	c.children_bounds = {
		.x = c.bounds.x,
		.y = c.bounds.y
	};
}

fn void? Ctx.layout_element_tree(&ctx)
{
	int current;
	for (int n; (current = ctx.tree.level_order_it(0, n)) >= 0; n++) {
		Elem* p = ctx.find_elem(ctx.tree.get(current))!;
		p.layout.origin = -p.layout.scroll_offset;

		int ch;
		// RESOLVE KNOWN DIMENSIONS
		for (int i; (ch = ctx.tree.children_it(current, i)) >= 0; i++) {
			Elem* c = ctx.find_elem(ctx.tree.get(ch))!;
			if (ctx.tree.is_root(ch)) {
				resolve_dimensions(p, &&{});
			} else {
				resolve_dimensions(c, p);
			}
		}

		// RESOLVE GROW CHILDREN
		for (int i; (ch = ctx.tree.children_it(current, i)) >= 0; i++) {
			Elem* c = ctx.find_elem(ctx.tree.get(ch))!;
			if (ctx.tree.is_root(ch)) {
				resolve_grow_elements(p, &&{});
			} else {
				resolve_grow_elements(c, p);
			}
		}

		// RESOLVE CHILDREN PLACEMENT
		for (int i; (ch = ctx.tree.children_it(current, i)) >= 0; i++) {
			Elem* c = ctx.find_elem(ctx.tree.get(ch))!;
			if (ctx.tree.is_root(ch)) {
				resolve_placement(p, &&{});
			} else {
				resolve_placement(c, p);
			}

			// FIXME: this stuff would be better elsewhere but we are already iteraring through all
			//        elements so here it fits really well
			ctx.update_hover_and_focus(c);
		}
	}
}
