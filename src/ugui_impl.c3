module ugui;

import std::io;

// return a pointer to the parent of the current active div
fn Elem*! Ctx.get_parent(&ctx)
{
	// FIXME: if the tree held pointers to the elements then no more
	//        redundant cache search
	Id parent_id = ctx.tree.get(ctx.active_div)!;
	return ctx.cache.search(parent_id);
}

fn void! Ctx.init(&ctx)
{
	ctx.tree.init(MAX_ELEMENTS)!;
	defer catch { (void)ctx.tree.free(); }
	//ug_fifo_init(&ctx.fifo, MAX_CMDS);

	ctx.cache.init()!;
	defer catch { (void)ctx.cache.free(); }

	ctx.cmd_queue.init(MAX_ELEMENTS)!;
	defer catch { (void)ctx.cmd_queue.free(); }

	ctx.layout = Layout.ROW;
	ctx.active_div = 0;

	// TODO: add style config
	ctx.style.margin  = Rect{1, 1, 1, 1};
}

fn void Ctx.free(&ctx)
{
	(void)ctx.tree.free();
	(void)ctx.cache.free();
	(void)ctx.cmd_queue.free();
}

fn void! Ctx.frame_begin(&ctx)
{
	// 1. Create the root div element
	// NOTE: in c3 everythong is zero initialized by default
	Rect space = {
	    .w = ctx.width,
	    .h = ctx.height,
	};

	Elem root = {
	    .id    = ROOT_ID,
	    .type  = ETYPE_DIV,
	    .rect  = space,
	    .div = {
		    .layout   = LAYOUT_ROW,
		},
	};

	// The root should have the updated flag only if the size of the window
	// was changed between frames, this propagates an element size recalculation
	// down the element tree
	if (ctx.input.events.resize) {
		root.flags.updated = true;
	}

	// if the window has focus then the root element also has focus, no other
	// computation needed, child elements need to check the mouse positon and
	// other stuff
	if (ctx.has_focus) {
		root.flags.has_focus = true;
	}

	// FIXME: check errors
	// 2. Get the root element from the cache and update it
	bool is_new;
	Elem empty_elem;
	Elem* c_elem = ctx.cache.get_or_insert(&empty_elem, root.id, &is_new)!;
	// flags always need to be set to the new flags
	c_elem.flags = root.flags;
	if (is_new || root.flags.updated) {
		*c_elem = root;
	}

	// 3. Push the root element into the element tree
	ctx.active_div = ctx.tree.add(root.id, 0)!;

	// print_tree(ctx);

	// The root element does not push anything to the stack
	// TODO: add a background color taken from a theme or config

	io::printn("##### Frame Begin #####");
}

fn void! Ctx.frame_end(&ctx)
{
	// 1. clear the tree
	ctx.tree.prune(0)!;

	// 2. clear input fields
	ctx.input.events = (InputEvents)0;

	// draw mouse position
$if 1:
	Cmd cmd = {
	    .type = CMD_RECT,
	    .rect.rect = {
		    .x = ctx.input.mouse.pos.x - 2,
		    .y = ctx.input.mouse.pos.y - 2,
		    .w = 4,
		    .h = 4,
		},
		.rect.color = uint_to_rgba(0xff00ffff)
	};
	ctx.cmd_queue.enqueue(&cmd)!;
$endif

	io::printn("##### Frame End #####");
}

fn void! Ctx.div_begin(&ctx, String label, Rect size)
{
	Id id = hash(label);

	bool is_new;
	Elem empty_elem;
	Elem* c_elem = ctx.cache.get_or_insert(&empty_elem, id, &is_new)!;

	// FIXME: why save the id in the tree and not something more direct like
	//        the element pointer or the index into the cache vector?
	isz div_node = ctx.tree.add(id, ctx.active_div)!;

	Elem *parent = ctx.get_parent()!;

	ctx.tree.print();

	// Use the current div
	ctx.active_div = div_node;

	// 1. Fill the element fields
	// this resets the flags
	c_elem.type  = ETYPE_DIV;
	c_elem.flags = (ElemFlags)0;

	// do layout and update flags only if the element was updated
	if (is_new || parent.flags.updated) {
		// 2. layout the element
		c_elem.rect = ctx.position_element(parent, size);

		// 3. Mark the element as updated
		c_elem.flags.updated = true;
		// 4. Fill the div fields
		c_elem.div.layout   = parent.div.layout;
		c_elem.div.origin_c = Point{
		    .x = c_elem.rect.x,
		    .y = c_elem.rect.y,
		};
		c_elem.div.color_bg = uint_to_rgba(0xff0000ff);
		c_elem.div.origin_r = c_elem.div.origin_c;
	} else if (parent.flags.has_focus) {
		if (point_in_rect(ctx.input.mouse.pos, c_elem.rect)) {
			c_elem.flags.has_focus = true;
		}
	} else {
		// TODO: check active
		// TODO: check scrollbars
		// TODO: check resizeable
	}

	// Add the background to the draw stack
	Cmd cmd = {
	    .type = CMD_RECT,
	    .rect = {
		    .rect  = c_elem.rect,
		    .color = c_elem.div.color_bg,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;
}

fn void! Ctx.div_end(&ctx)
{
	// the active_div returns to the parent of the current one
	ctx.active_div = ctx.tree.parentof(ctx.active_div)!;
}

// @ensure elem != null
fn bool Ctx.is_hovered(&ctx, Elem *elem)
{
	return point_in_rect(ctx.input.mouse.pos, elem.rect);
}

fn ElemEvents! Ctx.button(&ctx, String label, Rect size)
{
	Id id = hash(label);

	// TODO: do layouting if the element is new or the parent has updated
	bool is_new;
	Elem empty_elem;
	Elem *c_elem = ctx.cache.get_or_insert(&empty_elem, id, &is_new)!;

	// add it to the tree
	ctx.tree.add(id, ctx.active_div)!;
	ctx.tree.print();

	Elem *parent = ctx.get_parent()!;

	// 1. Fill the element fields
	// this resets the flags
	c_elem.type     = ETYPE_BUTTON;
	c_elem.flags    = (ElemFlags)0;
	Color bg_color = uint_to_rgba(0x0000ffff);

	// if the element is new or the parent was updated then redo layout
	if (is_new || parent.flags.updated) {
		// 2. Layout
		c_elem.rect = ctx.position_element(parent, size, true);

		// TODO: 3. Fill the button specific fields
	}

	// TODO: Check for interactions
	if (parent.flags.has_focus) {
		if (ctx.is_hovered(c_elem)) {
			c_elem.flags.has_focus = true;
			c_elem.events.mouse_hover = true;
			bg_color = uint_to_rgba(0x00ff00ff);
			c_elem.events.mouse_hold = ctx.input.mouse.down.btn_left;
		} else {
			c_elem.events.mouse_hover = false;
		}
	}

	// Draw the button
	Cmd cmd = {
	    .type = CMD_RECT,
	    .rect =	{
		    .rect  = c_elem.rect,
		    .color = bg_color,
		},
	};
	ctx.cmd_queue.enqueue(&cmd)!;

	return c_elem.events;
}
