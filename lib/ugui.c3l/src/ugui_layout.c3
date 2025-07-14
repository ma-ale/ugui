module ugui;

enum Layout {
	LAYOUT_ROW,
	LAYOUT_COLUMN,
	LAYOUT_FLOATING,
	LAYOUT_ABSOLUTE,
}

fn void? Ctx.layout_set_row(&ctx)
{
	Elem *parent = ctx.get_parent()!;
	parent.div.layout = LAYOUT_ROW;
}

fn void? Ctx.layout_set_column(&ctx)
{
	Elem *parent = ctx.get_parent()!;
	parent.div.layout = LAYOUT_COLUMN;
}

fn void? Ctx.layout_set_floating(&ctx)
{
	Elem *parent = ctx.get_parent()!;
	parent.div.layout = LAYOUT_FLOATING;
}

fn void? Ctx.layout_next_row(&ctx)
{
	Elem *parent = ctx.get_parent()!;

	parent.div.origin_r = {
		.x = parent.bounds.x,
		.y = parent.div.children_bounds.bottom_right().y,
	};
	parent.div.origin_c = parent.div.origin_r;
}

fn void? Ctx.layout_next_column(&ctx)
{
	Elem *parent = ctx.get_parent()!;

	parent.div.origin_c = {
		.x = parent.div.children_bounds.bottom_right().x,
		.y = parent.bounds.y,
	};
	parent.div.origin_r = parent.div.origin_c;
}

macro Rect Elem.content_bounds(&elem, style) => elem.bounds.pad(style.border).pad(style.padding);

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

// position the rectangle inside the parent according to the layout
// parent: parent div
// rect: the requested size
// style: apply style
<*
@require ctx != null
@require parent.type == ETYPE_DIV
*>
fn Rect Ctx.position_element(&ctx, Elem *parent, Rect rect, Style* style)
{
	ElemDiv* div = &parent.div;

	Rect parent_bounds, parent_view;
	Rect child_placement, child_occupied;

	// 1. Select the right origin
	Point origin;
	switch (div.layout) {
	case LAYOUT_ROW:
		origin = div.origin_r;
	case LAYOUT_COLUMN:
		origin = div.origin_c;
	case LAYOUT_FLOATING: // none, relative to zero zero
	case LAYOUT_ABSOLUTE: // absolute position, this is a no-op, return the rect
		return rect;
	default: // error
		return {};
	}

	// 2. Compute the parent's view
	parent_bounds = parent.bounds;
	parent_view = parent.get_view();

	// 3. Compute the placement and occupied area

	// grow rect (wanted size) when widht or height are less than zero
	bool adapt_x = rect.w <= 0;
	bool adapt_y = rect.h <= 0;
	if (adapt_x) rect.w = parent_bounds.w - parent_bounds.x - origin.x;
	if (adapt_y) rect.h = parent_bounds.h - parent_bounds.y - origin.y;

	// offset placement and area
	child_placement = child_placement.off(origin.add(rect.position()));
	child_occupied  = child_occupied.off(origin.add(rect.position()));

	Rect margin  = style.margin;
	Rect border  = style.border;
	Rect padding = style.padding;

	// padding, grows both the placement and occupied area
	child_placement = child_placement.grow(padding.position().add(padding.size()));
	child_occupied  = child_occupied.grow(padding.position().add(padding.size()));
	// border, grows both the placement and occupied area
	child_placement = child_placement.grow(border.position().add(border.size()));
	child_occupied  = child_occupied.grow(border.position().add(border.size()));
	// margin, offsets the placement and grows the occupied area
	child_placement = child_placement.off(margin.position());
	child_occupied  = child_occupied.grow(margin.position().add(margin.size()));

	// oh yeah also adjust the rect if i was to grow
	if (adapt_x) rect.w -= padding.x+padding.w + border.x+border.w + margin.x+margin.w;
	if (adapt_y) rect.h -= padding.y+padding.h + border.y+border.h + margin.y+margin.h;

	// set the size
	child_placement = child_placement.grow(rect.size());
	child_occupied  = child_occupied.grow(rect.size());

	// 4. Update the parent's origin
	div.origin_r = {
		.x = child_occupied.bottom_right().x,
		.y = origin.y,
	};
	div.origin_c = {
		.x = origin.x,
		.y = child_occupied.bottom_right().y,
	};

	// 5. Update the parent's children bounds
	if (!child_occupied.bottom_right().in_rect(div.children_bounds)) {
		// right overflow
		if (child_occupied.bottom_right().x > div.children_bounds.bottom_right().x) {
			div.children_bounds.w += child_occupied.bottom_right().x - div.children_bounds.bottom_right().x;
		}
		// bottom overflow
		if (child_occupied.bottom_right().y > div.children_bounds.bottom_right().y) {
			div.children_bounds.h += child_occupied.bottom_right().y - div.children_bounds.bottom_right().y;
		}
	}

	// 99. return the placement
	if (child_placement.collides(parent_view)) {
		return child_placement.off(parent.get_view_off().neg());
	} else {
		return {};
	}
}
