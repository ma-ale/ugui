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
	    .x = parent.rect.x,
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
	    .y = parent.rect.y,
	};
	parent.div.origin_r = parent.div.origin_c;
}

// position the rectangle inside the parent according to the layout
fn Rect Ctx.position_element(&ctx, Elem *parent, Rect rect, bool style = false)
{
	Rect  elem_rect;
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

	// 2. Position the rect
	elem_rect.x = origin.x + rect.x;
	elem_rect.y = origin.y + rect.y;

	// 3. Calculate width & height
	// TODO: what about negative values?
	// FIXME: account for origin offset!!
	elem_rect.w = rect.w > 0 ? rect.w : parent.rect.w;
	elem_rect.h = rect.h > 0 ? rect.h : parent.rect.h;

	// 4. Update the origins of the parent
	parent.div.origin_r = Point{
	    .x = elem_rect.x + elem_rect.w,
	    .y = elem_rect.y,
	};
	parent.div.origin_c = Point{
	    .x = elem_rect.x,
	    .y = elem_rect.y + elem_rect.h,
	};

	// if using the style then apply margins
	// FIXME: this does not work
	if (style && parent.div.layout != LAYOUT_FLOATING) {
		elem_rect.x += ctx.style.margin.x;
		elem_rect.y += ctx.style.margin.y;

		// total keep-out borders
		Rect margin_tot = {
		    .x = ctx.style.padding.x + ctx.style.border.x +
		         ctx.style.margin.x,
		    .y = ctx.style.padding.y + ctx.style.border.y +
		         ctx.style.margin.y,
		    .w = ctx.style.padding.w + ctx.style.border.x +
		         ctx.style.margin.w,
		    .h = ctx.style.padding.h + ctx.style.border.x +
		         ctx.style.margin.h,
		};

		parent.div.origin_r.x += margin_tot.x + margin_tot.w;
		// parent.div.origin_r.y += margin_tot.h;

		// parent.div.origin_c.x += margin_tot.w;
		parent.div.origin_c.y += margin_tot.y + margin_tot.h;
	}

	/*
	        printf(
	            "positioning rect: %lx {%d %d %d %d}(%d %d %d %d) . {%d %d %d
	   %d}\n", parent.id, rect.x, rect.y, rect.w, rect.h, parent.rect.x,
	            parent.rect.y,
	            parent.rect.w,
	            parent.rect.h,
	            elem_rect.x,
	            elem_rect.y,
	            elem_rect.w,
	            elem_rect.h
	        );
	*/
	return elem_rect;
}
