module ugui;


fn void! Ctx.layout_set_row(&ctx)
{
	Id parent_id = ctx.tree.get(ctx.active_div)!;
	Elem *parent = ctx.cache.search(parent_id)!;

	if (parent.type != ETYPE_DIV) {
		// what?
		return UgError.UNEXPECTED_ELEMENT?;
	}

	parent.div.layout = LAYOUT_ROW;
}

fn void! Ctx.layout_set_column(&ctx)
{
	Id parent_id = ctx.tree.get(ctx.active_div)!;
	Elem *parent = ctx.cache.search(parent_id)!;

	if (parent.type != ETYPE_DIV) {
		// what?
		return UgError.UNEXPECTED_ELEMENT?;
	}

	parent.div.layout = LAYOUT_COLUMN;
}

fn void! Ctx.layout_set_floating(&ctx)
{
	Id parent_id = ctx.tree.get(ctx.active_div)!;
	Elem *parent = ctx.cache.search(parent_id)!;

	if (parent.type != ETYPE_DIV) {
		// what?
		return UgError.UNEXPECTED_ELEMENT?;
	}

	parent.div.layout = LAYOUT_FLOATING;
}

fn void! Ctx.layout_next_row(&ctx)
{
	Id parent_id = ctx.tree.get(ctx.active_div)!;
	Elem *parent = ctx.cache.search(parent_id)!;

	if (parent.type != ETYPE_DIV) {
		// what?
		return UgError.UNEXPECTED_ELEMENT?;
	}

	parent.div.origin_r = Point{
	    .x = parent.bounds.x,
	    .y = parent.div.origin_c.y,
	};
	parent.div.origin_c = parent.div.origin_r;
}

fn void! Ctx.layout_next_column(&ctx)
{
	Id parent_id = ctx.tree.get(ctx.active_div)!;
	Elem *parent = ctx.cache.search(parent_id)!;

	if (parent.type != ETYPE_DIV) {
		// what?
		return UgError.UNEXPECTED_ELEMENT?;
	}

	parent.div.origin_c = Point{
	    .x = parent.div.origin_r.x,
	    .y = parent.bounds.y,
	};
	parent.div.origin_r = parent.div.origin_c;
}

// position the rectangle inside the parent according to the layout
// parent: parent div
// rect: the requested size
// style: apply style
fn Rect Ctx.position_element(&ctx, Elem *parent, Rect rect, bool style = false)
{
	Rect  placement;
	Point origin;

	// 1. Select the right origin
	switch (parent.div.layout) {
	case LAYOUT_ROW:
		origin = parent.div.origin_r;
	case LAYOUT_COLUMN:
		origin = parent.div.origin_c;
	case LAYOUT_FLOATING: // none
	default:
		// Error
	}

	// the bottom-right border of the element box
	Point pl_corner;

	// 2. Calculate the placement
	placement.x = (short)max(origin.x + rect.x, 0);
	placement.y = (short)max(origin.y + rect.y, 0);
	placement.w = rect.w > 0 ? rect.w : parent.bounds.w - (placement.x - parent.bounds.x);
	placement.h = rect.h > 0 ? rect.h : parent.bounds.h - (placement.y - parent.bounds.y);

	pl_corner.x = placement.x + placement.w;
	pl_corner.y = placement.y + placement.h;

	// 2.1 apply style, css box model
	if (style) {
	    Rect margin = ctx.style.margin;
	    Rect border = ctx.style.border;
		Rect padding = ctx.style.padding;

		placement.x += margin.x;
		placement.y += margin.y;
		if (rect.w != 0) { placement.w += margin.x+margin.w + padding.x+padding.w; }
		if (rect.h != 0) { placement.h += margin.y+margin.h + padding.y+padding.h; }

		pl_corner.x = placement.x + placement.w + margin.w;
		pl_corner.y = placement.y + placement.h + margin.h;
	}

	// 3. Update the origins of the parent
	parent.div.origin_r = Point{
	    .x = pl_corner.x,
	    .y = origin.y,
	};
	parent.div.origin_c = Point{
	    .x = origin.x,
	    .y = pl_corner.y,
	};

	// 4. Calculate the "scrolled" view
	Point off;
	if (parent.div.can_scroll_x && parent.div.horizontal_scroll_bar != -1) {
		Elem*! sx = ctx.get_elem_by_tree_idx(parent.div.horizontal_scroll_bar);
		if (catch sx) { return Rect{}; }
		// TODO: assert that the element is a slider
		off.x = (short)(parent.div.children_bounds.w * sx.slider.value);
	}
	if (parent.div.can_scroll_y && parent.div.vertical_scroll_bar != -1) {
		Elem*! sy = ctx.get_elem_by_tree_idx(parent.div.vertical_scroll_bar);
		if (catch sy) { return Rect{}; }
		// TODO: assert that the element is a slider
		off.y = (short)(parent.div.children_bounds.h * sy.slider.value);
	}
	Rect view = {
		.x = parent.bounds.x + off.x,
		.y = parent.bounds.y + off.y,
		.w = parent.bounds.w,
		.h = parent.bounds.h,
	};

	// TODO: 5. check if the placement is inside the view

	return placement;
}
