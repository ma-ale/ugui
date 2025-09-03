import vtree;
import std::io;
import std::math;
import std::thread;

const short WIDTH = 128;
const short HEIGHT = 64;

struct Size {
	short min, max;
}
macro Size @grow() => {.min = 0, .max = 0};
macro Size @exact(short s) => {.min = s, .max = s};
macro Size @fit(short min = 0, short max = short.max) => {.min = min, .max = max};
macro bool Size.@is_grow(s) => (s.min == 0 && s.max == 0);
macro bool Size.@is_exact(s) => (s.min == s.max && s.min != 0);
macro bool Size.@is_fit(s) => (s.min != s.max);



struct Rect {
	short x, y, w, h;
}

enum LayoutDirection {
	ROW,
	COLUMN
}

enum ElemType {
	DIV,
	ELEM
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

struct Elem {
	ElemType type;
	Size w, h;
	Rect bounds;
	Size ch_w, ch_h; // children width / height
	uint grow_children; // how many children want to grow, decreased once a child has grown
	short orig_x, orig_y;
	short occupied; // occupied space in the layout direction
	LayoutDirection layout_dir;
	Anchor anchor;
}

alias ElemTree = vtree::VTree{Elem*};


char[HEIGHT][WIDTH] screen;
fn void paint(Rect bounds, char c)
{
	for (short x = bounds.x; x < WIDTH && x < bounds.x + bounds.w; x++) {
		for (short y = bounds.y; y < HEIGHT && y < bounds.y + bounds.h; y++) {
			screen[x][y] = c;
		}
	}
}

fn isz Elem.div_start(&e, ElemTree* tree, isz parent, Size w, Size h, LayoutDirection dir = ROW, Anchor anchor = TOP_LEFT, char c = ' ')
{
	e.type = DIV;
	e.w = w;
	e.h = h;
	e.layout_dir = dir;
	e.anchor = anchor;

	e.grow_children = 0;
	e.occupied = 0;
	e.ch_w = e.ch_h = {};
	e.orig_x = e.orig_y = 0;

	// update grow children if necessary
	Elem* p = tree.get(parent) ?? &&{};
	if ((p.layout_dir == ROW && e.w.@is_grow()) || ((p.layout_dir == COLUMN && e.h.@is_grow()))) {
		p.grow_children++;
	}

	paint(e.bounds, c);
	return tree.add(e, parent)!!;
}

fn void update_parent_size(Elem* parent, Elem* child)
{
	// update the parent children size
	switch (parent.layout_dir) {
	case ROW: // on rows grow the ch width by the child width and only grow ch height if it exceeds
		parent.ch_w.min += child.w.min;
		parent.ch_w.max += child.w.max;
		parent.ch_h.min = math::max(child.h.min, parent.ch_h.min);
		parent.ch_h.max = math::max(child.h.max, parent.ch_h.max);
	case COLUMN: // do the opposite on column
		parent.ch_w.min = math::max(child.w.min, parent.ch_w.min);
		parent.ch_w.max = math::max(child.w.max, parent.ch_w.max);
		parent.ch_h.min += child.h.min;
		parent.ch_h.max += child.h.max;
	}
}

fn isz Elem.div_end(&e, ElemTree* tree, isz node)
{
	isz parent = tree.parentof(node) ?? -1;
	if (parent > 0) {
		Elem* p = tree.get(parent)!!;
		update_parent_size(p, e);
	}
	return parent;
}

fn void resolve_dimensions(Elem* e, Elem* p)
{
	// ASSIGN WIDTH
	switch {
	case e.w.@is_exact():
		e.bounds.w = e.w.min;
	case e.w.@is_grow():
		break;
		// done in another pass
	case e.w.@is_fit(): // fit the element's children
		short min = math::max(e.ch_w.min, e.w.min);
		short max = math::min(e.ch_w.max, e.w.max);
		if (max >= min) { // OK!
			e.bounds.w = max;
		} else {
			unreachable("cannot fit children");
		}
	default: unreachable("width is not exact, grow or fit");
	}

	// ASSIGN HEIGHT
	switch {
	case e.h.@is_exact():
		e.bounds.h = e.h.min;
	case e.h.@is_grow():
		break;
		// done in another pass
	case e.h.@is_fit(): // fit the element's children
		short min = math::max(e.ch_h.min, e.h.min);
		short max = math::min(e.ch_h.max, e.h.max);
		if (max >= min) { // OK!
			e.bounds.h = max;
		} else {
			unreachable("cannot fit children");
		}
	default: unreachable("width is not exact, grow or fit");
	}
	
	switch (p.layout_dir) {
	case ROW:
		if (!e.w.@is_grow()) p.occupied += e.bounds.w;
	case COLUMN:
		if (!e.h.@is_grow()) p.occupied += e.bounds.h;
	}
}

fn void resolve_grow_elements(Elem* e, Elem* p)
{
	// WIDTH
	if (e.w.@is_grow()) {
		if (p.layout_dir == ROW) { // grow along the axis, divide the parent size
			e.bounds.w = (short)((int)(p.bounds.w - p.occupied) / (int)p.grow_children);
			p.grow_children--;
			p.occupied += e.bounds.w;
		} else if (p.layout_dir == COLUMN) { // grow across the layout axis, inherit width of the parent
			e.bounds.w = p.bounds.w;
		}
	}
	
	// HEIGHT
	if (e.h.@is_grow()) {
		if (p.layout_dir == COLUMN) { // grow along the axis, divide the parent size
			e.bounds.h = (short)((int)(p.bounds.h - p.occupied) / (int)p.grow_children);
			p.grow_children--;
			p.occupied += e.bounds.h;
		} else if (p.layout_dir == ROW) { // grow across the layout axis, inherit width of the parent
			e.bounds.h = p.bounds.h;
		}
	}
}

fn void resolve_placement(Elem* e, Elem* p)
{
	switch (p.anchor) {
	case TOP_LEFT:
		e.bounds.x = p.bounds.x + p.orig_x;
		e.bounds.y = p.bounds.y + p.orig_y;
	case LEFT:
		e.bounds.x = p.bounds.x + p.orig_x;
		e.bounds.y = p.bounds.y + p.orig_y + p.bounds.h/2;
		if (p.layout_dir == COLUMN) {
			e.bounds.y -= p.occupied/2;
		} else if (p.layout_dir == ROW) {
			e.bounds.y -= e.bounds.h/2;
		}
	case BOTTOM_LEFT:
		e.bounds.x = p.bounds.x + p.orig_x;
		e.bounds.y = p.bounds.y + p.bounds.h + p.orig_y;
		if (p.layout_dir == COLUMN) {
			e.bounds.y -= p.occupied;
		} else if (p.layout_dir == ROW) {
			e.bounds.y -= e.bounds.h;
		}
	case BOTTOM:
		e.bounds.x = p.bounds.x + p.orig_x + p.bounds.w/2;
		e.bounds.y = p.bounds.y + p.bounds.h + p.orig_y;
		if (p.layout_dir == COLUMN) {
			e.bounds.y -= p.occupied;
			e.bounds.x -= e.bounds.w/2;
		} else if (p.layout_dir == ROW) {
			e.bounds.y -= e.bounds.h;
			e.bounds.x -= p.occupied/2;
		}
	case BOTTOM_RIGHT:
		e.bounds.x = p.bounds.x + p.orig_x + p.bounds.w;
		e.bounds.y = p.bounds.y + p.bounds.h + p.orig_y;
		if (p.layout_dir == COLUMN) {
			e.bounds.y -= p.occupied;
			e.bounds.x -= e.bounds.w;
		} else if (p.layout_dir == ROW) {
			e.bounds.y -= e.bounds.h;
			e.bounds.x -= p.occupied;
		}
	case RIGHT:
		e.bounds.x = p.bounds.x + p.orig_x + p.bounds.w;
		e.bounds.y = p.bounds.y + p.orig_y + p.bounds.h/2;
		if (p.layout_dir == COLUMN) {
			e.bounds.y -= p.occupied/2;
			e.bounds.x -= e.bounds.w;
		} else if (p.layout_dir == ROW) {
			e.bounds.y -= e.bounds.h/2;
			e.bounds.x -= p.occupied;
		}
	case TOP_RIGHT:
		e.bounds.x = p.bounds.x + p.orig_x + p.bounds.w;
		e.bounds.y = p.bounds.y + p.orig_y;
		if (p.layout_dir == COLUMN) {
			e.bounds.x -= e.bounds.w;
		} else if (p.layout_dir == ROW) {
			e.bounds.x -= p.occupied;
		}
	case TOP:
		e.bounds.x = p.bounds.x + p.orig_x + p.bounds.w/2;
		e.bounds.y = p.bounds.y + p.orig_y;
		if (p.layout_dir == COLUMN) {
			e.bounds.x -= e.bounds.w/2;
		} else if (p.layout_dir == ROW) {
			e.bounds.x -= p.occupied/2;
		}
	case CENTER:
		e.bounds.x = p.bounds.x + p.orig_x + p.bounds.w/2;
		e.bounds.y = p.bounds.y + p.orig_y + p.bounds.h/2;
		if (p.layout_dir == COLUMN) {
			e.bounds.x -= e.bounds.w/2;
			e.bounds.y -= p.occupied/2;
		} else if (p.layout_dir == ROW) {
			e.bounds.x -= p.occupied/2;
			e.bounds.y -= e.bounds.h/2;
		}
		break;
	}

/*
	e.bounds.x = p.bounds.x + p.orig_x;
	e.bounds.y = p.bounds.y + p.orig_y;
*/

	switch (p.layout_dir) {
	case ROW:
		p.orig_x += e.bounds.w;
	case COLUMN:
		p.orig_y += e.bounds.h;
	default: unreachable("unknown layout direction");
	}
}

fn void frame_end(ElemTree* tree, isz root)
{
	// assign the element bounds
	isz cursor = -1;

	/*
	// RESOLVE DIMENSIONS
	isz current = tree.level_order_it(root, &cursor)!!;
	for (; current >= 0; current = tree.level_order_it(root, &cursor)!!) {
		Elem* e = tree.get(current)!!;
		isz pi = tree.parentof(current)!!;
		Elem* p = (pi != current) ? tree.get(pi) ?? &&{} : &&{};
		resolve_dimensions(e, p);
	}
	
	// RESOLVE GROW ELEMENTS
	cursor = -1;
	current = tree.level_order_it(root, &cursor)!!;
	for (; current >= 0; current = tree.level_order_it(root, &cursor)!!) {
		Elem* e = tree.get(current)!!;
		isz pi = tree.parentof(current)!!;			if (ch == current) continue;
		Elem* p = (pi != current) ? tree.get(pi) ?? &&{} : &&{};

		resolve_grow_elements(e, p);
	}


	// RESOLVE PLACEMENT
	cursor = -1;
	current = tree.level_order_it(root, &cursor)!!;
	for (; current >= 0; current = tree.level_order_it(root, &cursor)!!) {
		Elem* e = tree.get(current)!!;
		isz pi = tree.parentof(current)!!;
		Elem* p = (pi != current) ? tree.get(pi) ?? &&{} : &&{};

		resolve_placement(e, p);
	}
	*/

	cursor = -1;
	isz current = tree.level_order_it(root, &cursor)!!;
	for (; current >= 0; current = tree.level_order_it(root, &cursor)!!) {
		Elem* p = tree.get(current)!!;

		// RESOLVE KNOWN DIMENSIONS
		isz ch_cur = 0;
		isz ch = tree.children_it(current, &ch_cur)!!;
		for (; ch >= 0; ch = tree.children_it(current, &ch_cur)!!) {
			Elem* c = tree.get(ch)!!;
			if (tree.is_root(ch)!!) {
				resolve_dimensions(p, &&{});
			} else {
				resolve_dimensions(c, p);
			}
		}

		// RESOLVE GROW CHILDREN
		ch_cur = 0;
		ch = tree.children_it(current, &ch_cur)!!;
		for (; ch >= 0; ch = tree.children_it(current, &ch_cur)!!) {
			Elem* c = tree.get(ch)!!;
			if (tree.is_root(ch)!!) {
				resolve_grow_elements(p, &&{});
			} else {
				resolve_grow_elements(c, p);
			}
		}
		
		// RESOLVE CHILDREN PLACEMENT
		ch_cur = 0;
		ch = tree.children_it(current, &ch_cur)!!;
		for (; ch >= 0; ch = tree.children_it(current, &ch_cur)!!) {
			Elem* c = tree.get(ch)!!;
			if (tree.is_root(ch)!!) {
				resolve_placement(p, &&{});
			} else {
				resolve_placement(c, p);
			}
		}
	}
}

fn void main()
{
	ElemTree tree;
	tree.init(64, mem)!!;
	isz parent;
	defer (void)tree.free();

	Elem root; // root div
	Elem div1, div2, div3, div4;
	usz frame;
	while (true) {
		parent = root.div_start(&tree, parent, @exact(WIDTH), @exact(HEIGHT), ROW, anchor: RIGHT);
		/*
		{
			parent = div1.div_start(&tree, parent, @grow(), @grow(), dir: ROW, c: '1');
			{
				parent = div4.div_start(&tree, parent, @exact(30), @exact(30), dir: ROW, c: '4');
				parent = div4.div_end(&tree, parent);
			}
			parent = div1.div_end(&tree, parent);

			if (frame < 200) {
				parent = div2.div_start(&tree, parent, @exact(20), @fit(), dir: COLUMN, c: '2');
				{
					parent = div3.div_start(&tree, parent, @exact(10), @exact(10), dir: ROW, c: '3');
					parent = div3.div_end(&tree, parent);
				}
				parent = div2.div_end(&tree, parent);
			}
		}
		*/
		parent = div3.div_start(&tree, parent, @fit(), @fit(), COLUMN, anchor: CENTER);
		{
			parent = div1.div_start(&tree, parent, @exact(20), @exact(20), dir: ROW, c: '1');
			parent = div1.div_end(&tree, parent);
	
			parent = div2.div_start(&tree, parent, @exact(10), @exact(10), dir: ROW, c: '2');
			parent = div2.div_end(&tree, parent);
		}
		parent = div3.div_end(&tree, parent);

		parent = root.div_end(&tree, parent);
		
		frame_end(&tree, parent);
		tree.nuke();
		

		// draw the screen
		//io::print("\e[1;1H\e[2J");
		for (short x = 0; x < WIDTH+2; x++) io::printf("%c", x == 0 || x == WIDTH+1 ? '+' : '-');
		io::printn();
		for (short y = 0; y < HEIGHT; y++) {
			io::print("|");
			for (short x = 0; x < WIDTH; x++) {
				char c = screen[x][y] == 0 ? 'x' : screen[x][y];
				io::printf("%c", c);
			}
			io::print("|");
			io::printn();
		}
		for (short x = 0; x < WIDTH+2; x++) io::printf("%c", x == 0 || x == WIDTH+1 ? '+' : '-');
		io::printn("\n\n");

		thread::sleep_ms(10);
		frame++;
	}
}