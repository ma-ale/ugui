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
<*
@require ctx != null
@require parent.type == ETYPE_DIV
*>
fn Rect Ctx.position_element(&ctx, Elem *parent, Rect rect, bool style = false)
{
	Rect placement;
	Point origin;
	ElemDiv* div = &parent.div;

	// 1. Select the right origin
	switch (div.layout) {
	case LAYOUT_ROW:
		origin = div.origin_r;
	case LAYOUT_COLUMN:
		origin = div.origin_c;
	case LAYOUT_FLOATING: // none, relative to zero zero
	case LAYOUT_ABSOLUTE: // absolute position, this is a no-op, return the rect
		return rect;
	default: // error
		return Rect{};
	}

	// the bottom-right border of the element box
	Point pl_corner;

	// 2. Calculate the placement
	placement.x = (short)max(origin.x + rect.x, 0);
	placement.y = (short)max(origin.y + rect.y, 0);
	placement.w = rect.w > 0 ? rect.w : (short)max(parent.bounds.w - (placement.x - parent.bounds.x), 0);
	placement.h = rect.h > 0 ? rect.h : (short)max(parent.bounds.h - (placement.y - parent.bounds.y), 0);

	pl_corner.x = placement.x + placement.w;
	pl_corner.y = placement.y + placement.h;

	// 2.1 apply style, css box model
	if (style) {
		Rect margin = ctx.style.margin;
		Rect border = ctx.style.border;
		Rect padding = ctx.style.padding;

		placement.x += margin.x;
		placement.y += margin.y;
		if (rect.w != 0) { placement.w += border.x+border.w + padding.x+padding.w; }
		if (rect.h != 0) { placement.h += border.y+border.h + padding.y+padding.h; }

		pl_corner.x = placement.x + placement.w + margin.w;
		pl_corner.y = placement.y + placement.h + margin.h;
	}

	// 3. Update the origins of the parent
	div.origin_r = Point{
		.x = pl_corner.x,
		.y = origin.y,
	};
	div.origin_c = Point{
		.x = origin.x,
		.y = pl_corner.y,
	};

	// 4. Calculate the "scrolled" view
	Point off;
	Rect* cb = &div.children_bounds;
	if (div.scroll.can_x && div.scroll.on_x) {
		off.x = (short)((float)(div.pcb.w - parent.bounds.w) * div.scroll.value_x);
	}
	if (div.scroll.can_y && div.scroll.on_y) {
		off.y = (short)((float)(div.pcb.h - parent.bounds.h) * div.scroll.value_y);
	}
	Rect view = {
		.x = parent.bounds.x + off.x,
		.y = parent.bounds.y + off.y,
		.w = parent.bounds.w,
		.h = parent.bounds.h,
	};

	// 5. check if the placement overflows the children ounds, if so update them
	if (!point_in_rect(pl_corner, *cb)) {
		if (pl_corner.y > cb.y+cb.h) {
			cb.h = pl_corner.y - cb.y;
		}
		if (pl_corner.x > cb.x+cb.w) {
			cb.w += pl_corner.x - (cb.x + cb.w);
		}
	}

	// 6. check if the placement is inside the view
	if (placement.collides(view)) {
		return Rect{
			.x = placement.x - off.x,
			.y = placement.y - off.y,
			.w = placement.w,
			.h = placement.h,
		};
	} else {
		return Rect{};
	}
}

