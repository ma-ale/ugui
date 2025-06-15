module ugui;

import vtree;
import cache;
import fifo;

import std::io;
import std::core::string;


// element ids are just long ints
alias Id = usz;

enum ElemType {
	ETYPE_NONE,
	ETYPE_DIV,
	ETYPE_BUTTON,
	ETYPE_SLIDER,
	ETYPE_TEXT,
	ETYPE_SPRITE,
}

bitstruct ElemFlags : uint {
	bool updated : 0;
	bool is_new : 1;
}

bitstruct ElemEvents : uint {
	bool key_press     : 0;
	bool key_release   : 1;
	bool key_hold      : 2;
	bool mouse_hover   : 3;
	bool mouse_press   : 4;
	bool mouse_release : 5;
	bool mouse_hold    : 6;
	bool update        : 7;
}

// element structure
struct Elem {
	Id id;
	ElemFlags flags;
	ElemEvents events;
	Rect bounds;
	ElemType type;
	union {
		ElemDiv div;
		ElemButton button;
		ElemSlider slider;
		ElemText text;
		ElemSprite sprite;
	}
}


// relationships between elements are stored in a tree, it stores just the ids
alias IdTree = vtree::VTree{Id};

// elements themselves are kept in a cache
const uint MAX_ELEMENTS = 256;
alias ElemCache = cache::Cache{Id, Elem, MAX_ELEMENTS};

alias CmdQueue = fifo::Fifo{Cmd};

faultdef INVALID_SIZE, EVENT_UNSUPPORTED, UNEXPECTED_ELEMENT, WRONG_ELEMENT_TYPE, WRONG_ID;

const Rect DIV_FILL = { .x = 0, .y = 0, .w = 0, .h = 0 };

const uint STACK_STEP = 10;
const uint MAX_ELEMS  = 128;
const uint MAX_CMDS   = 2048;
const uint ROOT_ID    = 1;
const uint TEXT_MAX   = 64;

// global style, similar to the css box model
struct Style { // css box model
	Rect  padding;
	Rect  border;
	Rect  margin;
	Color bgcolor; // background color
	Color fgcolor; // foreground color
	Color brcolor; // border color
	ushort radius;
}


struct Ctx {
	IdTree tree;
	ElemCache cache;
	CmdQueue cmd_queue;
	// total size in pixels of the context
	ushort width, height;
	Style style;
	Font font;
	SpriteAtlas sprite_atlas;

	bool has_focus;
	struct input {
		InputEvents events;
		struct mouse {
			Point pos, delta;
			// mouse_down:      bitmap of mouse buttons that are held
			// mouse_updated:   bitmap of mouse buttons that have been updated
			// mouse_released = mouse_updated & ~mouse_down
			// mouse_pressed  = mouse_updated & mouse_down
			MouseButtons down;
			MouseButtons updated;
			// scroll wheel
			Point scroll;
		}
		struct keyboard {
			char[TEXT_MAX] text;
			usz text_len;
			ModKeys down;
		}
	}

	Id hover_id;
	Id focus_id;

	Rect div_scissor; // the current div bounds used for scissor test
	isz active_div; // tree node indicating the current active div
}

// return a pointer to the parent of the current active div
fn Elem*? Ctx.get_parent(&ctx)
{
	Id parent_id = ctx.tree.get(ctx.active_div)!;
	return ctx.cache.search(parent_id);
}

macro @bits(#a) => $typeof(#a).sizeof*8;
macro Id.rotate_left(id, uint $n) => (id << $n) | (id >> (@bits(id) - $n));
const uint GOLDEN_RATIO = 0x9E3779B9;

// generate an id combining the hashes of the parent id and the label
// with the Cantor pairing function
macro Id? Ctx.gen_id(&ctx, String label)
{
	Id id1 = ctx.tree.get(ctx.active_div)!;
	Id id2 = label.hash();
	// Mix the two IDs non-linearly
	Id mixed = id1 ^ id2.rotate_left(13);
	mixed ^= id1.rotate_left(7);
	mixed += GOLDEN_RATIO;
	return mixed;
}

// get or push an element from the cache, return a pointer to it
// resets all flags except is_new which is set accordingly
fn Elem*? Ctx.get_elem(&ctx, Id id)
{
	Elem empty_elem;
	bool is_new;
	Elem* elem;
	elem = ctx.cache.get_or_insert(&empty_elem, id, &is_new)!;
	elem.flags = (ElemFlags)0;
	elem.flags.is_new = is_new;
	// FIXME: should this be here? or is it better to have the elements set the id?
	elem.id = id;
	return elem;
}

// find an element, does not allocate a new one in cache
// THIS HAS TO BE A MACRO SINCE IT RETURNS A POINTER TO A TEMPORARY VALUE
macro Elem* Ctx.find_elem(&ctx, Id id)
{
	Elem*? elem;
	elem = ctx.cache.search(id);
	if (catch elem) {
		return &&(Elem){};
	}
	return elem;
}

// FIXME: Since ids are now keyed with the element's parent id, this function does not work
//        outside of the element's div block.
// this searches an element in the cache by label, it does not create a new element
// if it does't find one
//macro Ctx.get_elem_by_label(&ctx, String label)
//{
//	Id id = ctx.get_id(label);
//	return ctx.cache.search(id);
//}

macro Ctx.get_elem_by_tree_idx(&ctx, isz idx) @private
{
	Id id = ctx.tree.get(ctx.active_div)!;
	return ctx.cache.search(id);
}

fn void? Ctx.init(&ctx)
{
	ctx.tree.init(MAX_ELEMENTS)!;
	defer catch { (void)ctx.tree.free(); }

	ctx.cache.init()!;
	defer catch { (void)ctx.cache.free(); }

	ctx.cmd_queue.init(MAX_CMDS)!;
	defer catch { (void)ctx.cmd_queue.free(); }

	ctx.active_div = 0;

	// TODO: add style config
	ctx.style.margin  = {2, 2, 2, 2};
	ctx.style.border  = {2, 2, 2, 2};
	ctx.style.padding = {1, 1, 1, 1};
	ctx.style.radius  = 12;
	ctx.style.bgcolor = 0x282828ffu.to_rgba();
	ctx.style.fgcolor = 0xfbf1c7ffu.to_rgba();
	ctx.style.brcolor = 0xd79921ffu.to_rgba();
}

fn void Ctx.free(&ctx)
{
	(void)ctx.tree.free();
	(void)ctx.cache.free();
	(void)ctx.cmd_queue.free();
	(void)ctx.font.free();
	(void)ctx.sprite_atlas.free();
}

fn void? Ctx.frame_begin(&ctx)
{

	// 2. Get the root element from the cache and update it
	Elem* elem = ctx.get_elem(ROOT_ID)!;
	// The root should have the updated flag only if the size of the window
	// was changed between frames, this propagates an element size recalculation
	// down the element tree
	elem.flags.updated = ctx.input.events.resize;
	// if the window has focus then the root element also has focus, no other
	// computation needed, child elements need to check the mouse positon and
	// other stuff
	//elem.flags.has_focus = ctx.has_focus;

	Elem def_root = {
		.id = ROOT_ID,
		.type = ETYPE_DIV,
		.bounds = {
			.w = ctx.width,
			.h = ctx.height,
		},
		.div = {
			.layout = LAYOUT_ROW,
			.z_index = 0,
			.children_bounds = {
				.w = ctx.width,
				.h = ctx.height,
			}
		},
		.flags = elem.flags,
	};

	*elem = def_root;

	// 3. Push the root element into the element tree
	ctx.active_div = ctx.tree.add(ROOT_ID, 0)!;

	ctx.div_scissor = {0, 0, ctx.width, ctx.height};

	// The root element does not push anything to the stack
	// TODO: add a background color taken from a theme or config
}

const int DEBUG = 1;

fn void? Ctx.frame_end(&ctx)
{
	Elem* root = ctx.get_elem_by_tree_idx(0)!;
	root.div.layout = LAYOUT_ROW;

	// 1. clear the tree
	ctx.tree.nuke();

	// 2. clear input fields
	ctx.input.events = (InputEvents)0;
	ctx.input.keyboard.text_len = 0;

	// send atlas updates
	if (ctx.font.should_update) {
		ctx.push_update_atlas(&ctx.font.atlas)!;
		ctx.font.should_update = false;
	}
	if (ctx.sprite_atlas.should_update) {
		ctx.push_update_atlas(&ctx.sprite_atlas.atlas)!;
		ctx.sprite_atlas.should_update = false;
	}

// debug
$if DEBUG == 1:
	// draw mouse position
	Cmd cmd = {
		.type = CMD_RECT,
		.z_index = int.max-1, // hopefully over everything else
		.rect.rect = {
			.x = ctx.input.mouse.pos.x - 2,
			.y = ctx.input.mouse.pos.y - 2,
			.w = 4,
			.h = 4,
		},
		.rect.color = 0xff00ffffu.to_rgba()
	};
	ctx.cmd_queue.enqueue(&cmd)!;
$endif

	// sort the command buffer by the z-index
	ctx.cmd_queue.sort()!;
}

<*
 * @ensure elem != null
*>
macro bool Ctx.is_hovered(&ctx, Elem *elem)
{
	return ctx.input.mouse.pos.in_rect(elem.bounds);
}

macro bool Ctx.elem_focus(&ctx, Elem *elem)
{
	return ctx.focus_id == elem.id;
}

// TODO: add other events
// FIXME: this does not work with touch
// FIXME: hacked together, please do better
fn ElemEvents Ctx.get_elem_events(&ctx, Elem *elem)
{
	bool hover = ctx.is_hovered(elem);
	bool focus = ctx.focus_id == elem.id || (hover && ctx.is_mouse_pressed(BTN_LEFT));

	if (ctx.is_mouse_pressed(BTN_ANY) && !hover){
		focus = false;
		if (ctx.focus_id == elem.id) ctx.focus_id = 0;
	}

	if (hover) { ctx.hover_id = elem.id; }
	if (focus) { ctx.focus_id = elem.id; }

	ElemEvents ev = {
		.mouse_hover = hover,
		.mouse_press = hover && focus && ctx.is_mouse_pressed(BTN_ANY),
		.mouse_release = hover && focus && ctx.is_mouse_released(BTN_ANY),
		.mouse_hold = hover && focus && ctx.is_mouse_down(BTN_ANY),
	};
	return ev;
}
