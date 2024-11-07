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

// get or push an element from the cache, return a pointer to it
// resets all flags except is_new which is set accordingly
macro Ctx.get_elem(&ctx, Id id)
{
	Elem empty_elem;
	bool is_new;
	Elem* c_elem;
	c_elem = ctx.cache.get_or_insert(&empty_elem, id, &is_new)!;
	c_elem.flags = (ElemFlags)0;
	c_elem.flags.is_new = is_new;
	return c_elem;
}

// this searches an element in the cache by label, it does not create a new element
// if it does't find one
macro Ctx.get_elem_by_label(&ctx, String label)
{
    Id id = hash(label);
    return ctx.cache.search(id);
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

	// 2. Get the root element from the cache and update it
	Elem* c_elem = ctx.get_elem(ROOT_ID)!;
	// The root should have the updated flag only if the size of the window
	// was changed between frames, this propagates an element size recalculation
	// down the element tree
	c_elem.flags.updated = ctx.input.events.resize;
	// if the window has focus then the root element also has focus, no other
	// computation needed, child elements need to check the mouse positon and
	// other stuff
	c_elem.flags.has_focus = ctx.has_focus;

	if (c_elem.flags.is_new || c_elem.flags.updated) {
        Elem def_root = {
            .id = ROOT_ID,
            .type = ETYPE_DIV,
            .bounds = {
                .w = ctx.width,
                .h = ctx.height,
            },
            .div = {
                .layout = LAYOUT_ROW,
            },
            .flags = c_elem.flags,
        };

        *c_elem = def_root;
	}

	// 3. Push the root element into the element tree
	ctx.active_div = ctx.tree.add(ROOT_ID, 0)!;

	// The root element does not push anything to the stack
	// TODO: add a background color taken from a theme or config
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
}

/**
 * @ensure elem != null
**/
fn bool Ctx.is_hovered(&ctx, Elem *elem)
{
	return point_in_rect(ctx.input.mouse.pos, elem.bounds);
}
