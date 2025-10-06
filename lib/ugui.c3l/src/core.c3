module ugui;

import mtree;
import cache;


import std::io;
import std::core::string;
import std::core::mem::allocator;
import std::collections::pair;
import std::sort;


macro println(...)
{
	$for var $i = 0; $i < $vacount; $i++:
		io::print($vaexpr[$i]);
	$endfor
	io::printn();
}


// element ids are just long ints
alias Id = uint;

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
	bool key_repeat    : 2;
	bool mouse_hover   : 3;
	bool mouse_press   : 4;
	bool mouse_release : 5;
	bool mouse_hold    : 6;
	bool update        : 7;
	bool text_input    : 8;
	bool has_focus     : 9;
}

// element structure
struct Elem {
	Id id;
	int tree_idx;
	ElemFlags flags;
	ElemEvents events;
	Rect bounds;
	Rect children_bounds;
	ElemType type;
	Layout layout;
	int z_index;
	union {
		ElemDiv div;
		ElemButton button;
		ElemSlider slider;
		ElemText text;
		ElemSprite sprite;
	}
}


const uint MAX_ELEMENTS = 256;
const uint MAX_COMMANDS = 2048;
const uint STACK_STEP = 10;
const uint ROOT_ID    = 1;
const uint TEXT_MAX   = 64;


// Tuple of Element pointers, used when it is useful to get both parent and child
alias PElemTuple = pair::Pair{Elem*, Elem*};

// relationships between elements are stored in a tree, it stores just the ids
alias IdTree = mtree::MTree{Id};

// elements themselves are kept in a cache
alias ElemCache = cache::Cache{Id, Elem, MAX_ELEMENTS};

faultdef INVALID_SIZE, EVENT_UNSUPPORTED, WRONG_ELEMENT_TYPE, WRONG_ID;

struct Ctx {
	IdTree tree;
	ElemCache cache;
	CmdQueue cmd_queue;
	StyleMap styles;
	// total size in pixels of the context
	ushort width, height;
	Font font;
	SpriteAtlas sprite_atlas;

	bool has_focus;
	struct input {
		InputEvents events;
		int z_index; // the layer the input events need to be propageted to
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
			ModKeys modkeys;
		}
	}

	Id hover_id;
	Id focus_id;

	Rect div_scissor; // the current div bounds used for scissor test
	int active_div; // tree node indicating the current active div
}

// return a pointer to the parent of the current active div
fn Elem*? Ctx.get_parent(&ctx)
{
	Id parent_id = ctx.tree[ctx.active_div]!;
	Elem* parent = ctx.cache.search(parent_id)!;
	return parent;
}

macro @bits(#a) => $typeof(#a).sizeof*8;
macro Id.rotate_left(id, uint $n) => (id << $n) | (id >> (@bits(id) - $n));
const uint GOLDEN_RATIO = 0x9E3779B9;

// generate an id combining the hashes of the parent id and the label
// with the Cantor pairing function
fn Id? Ctx.gen_id(&ctx, Id id2)
{
	// FIXME: this is SHIT
	Id id1 = ctx.tree.get(ctx.active_div)!;
	// Mix the two IDs non-linearly
	Id mixed = id1 ^ id2.rotate_left(13);
	mixed ^= id1.rotate_left(7);
	mixed += GOLDEN_RATIO;
	return mixed;
}

// compute the id from arguments and the line of the call
macro Id @compute_id(...)
{
	Id id = (Id)$$LINE.hash() ^ (Id)@str_hash($$FILE);
	$for var $i = 0; $i < $vacount; $i++:
		id ^= (Id)$vaconst[$i].hash();
	$endfor
	return id;
}

// get or push an element from the cache, return a pointer to it
// resets all flags except is_new which is set accordingly
fn PElemTuple? Ctx.get_elem(&ctx, Id id, ElemType type)
{
	bool is_new;
	Elem* parent;
	Elem* elem;
	parent = ctx.get_parent() ?? &&(Elem){};

	elem = ctx.cache.get_or_insert(&&(Elem){}, id, &is_new)!;
	elem.flags = (ElemFlags)0;
	elem.flags.is_new = is_new;
	elem.id = id;
	elem.layout = {};
	if (is_new == false && elem.type != type) {
		return WRONG_ELEMENT_TYPE?;
	} else {
		elem.type = type;
	}
	elem.z_index = parent.z_index;
	elem.tree_idx = ctx.tree.add(ctx.active_div, id)!;
	return {elem, parent};
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

fn Elem*? Ctx.get_active_div(&ctx)
{
	Id id = ctx.tree.get(ctx.active_div)!;
	return ctx.cache.search(id);
}

fn void? Ctx.init(&ctx, Allocator allocator)
{
	ctx.tree.init(MAX_ELEMENTS, allocator);
	defer catch { (void)ctx.tree.free(); }

	ctx.cache.init(allocator)!;
	defer catch { (void)ctx.cache.free(); }

	ctx.cmd_queue.init(allocator::mem, MAX_COMMANDS);
	defer catch { (void)ctx.cmd_queue.free(); }

	ctx.styles.init(allocator);
	ctx.styles.register_style(&DEFAULT_STYLE, @str_hash("default"));
	defer catch { ctx.styles.free(); }

	ctx.active_div = 0;
}

fn void Ctx.free(&ctx)
{
	(void)ctx.tree.free();
	(void)ctx.cache.free();
	(void)ctx.cmd_queue.free();
	(void)ctx.font.free();
	(void)ctx.sprite_atlas.free();
	(void)ctx.styles.free();
}

fn void? Ctx.frame_begin(&ctx)
{
	// 1. Reset the active div
	// 2. Get the root element from the cache and update it
	ctx.active_div = 0;
	Elem* elem = ctx.get_elem(ROOT_ID, ETYPE_DIV)!.first;
	ctx.active_div = elem.tree_idx;
	// The root should have the updated flag only if the size of the window
	// was changed between frasmes, this propagates an element size recalculation
	// down the element tree
	elem.flags.updated = ctx.input.events.resize;
	// if the window has focus then the root element also has focus, no other
	// computation needed, child elements need to check the mouse positon and
	// other stuff
	ctx.input.z_index = 0;
	//elem.flags.has_focus = ctx.has_focus;

	elem.bounds = {0, 0, ctx.width, ctx.height};
	elem.z_index = 0;
	elem.div.scroll_x.enabled = false;
	elem.div.scroll_y.enabled = false;
	elem.layout.dir = ROW;
	elem.layout.anchor = TOP_LEFT;
	elem.layout.w = @exact(ctx.width);
	elem.layout.h = @exact(ctx.height);

	ctx.div_scissor = elem.bounds;

	// The root element does not push anything to the stack
	// TODO: add a background color taken from a theme or config
}

fn void? Ctx.frame_end(&ctx)
{
	// FIXME: this is not guaranteed to be root. the user might forget to close a div or some other element
	Elem* root = ctx.get_active_div()!;
	if (root.id != ROOT_ID) {
		io::printn(root.id);
		return WRONG_ID?;
	}

	// DO THE LAYOUT
	ctx.layout_element_tree()!;

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
$if $feature(DEBUG_POINTER):
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
	ctx.cmd_queue.push(cmd);
$endif

	// sort the command buffer by the z-index
	// FIXME: sorting the buffer fucks with scissor commands that have to be kept in place
	// TODO: instead of sorting at the end perform ordered inserts into the command buffer
	sort::countingsort(ctx.cmd_queue, fn uint(Cmd c) => c.z_index+1);

//	foreach (i, c: ctx.cmd_queue) {
//		io::printf("[%d]: ", i);
//		io::printn(c);
//	}
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
	if (ctx.input.z_index != elem.z_index) return {};

	bool hover = ctx.is_hovered(elem);
	bool focus = ctx.elem_focus(elem) || (hover && ctx.is_mouse_pressed(BTN_LEFT));

	if (ctx.is_mouse_pressed(BTN_ANY) && !hover){
		focus = false;
		if (ctx.focus_id == elem.id) ctx.focus_id = 0;
	}

	if (hover) { ctx.hover_id = elem.id; }
	if (focus) { ctx.focus_id = elem.id; }

	ElemEvents ev = {
		.has_focus     = focus,
		.mouse_hover   = hover,
		.mouse_press   = hover && focus && ctx.is_mouse_pressed(BTN_ANY),
		.mouse_release = hover && focus && ctx.is_mouse_released(BTN_ANY),
		.mouse_hold    = hover && focus && ctx.is_mouse_down(BTN_ANY),
		.key_press     = focus && ctx.input.events.key_press,
		.key_release   = focus && ctx.input.events.key_release,
		.key_repeat    = focus && ctx.input.events.key_repeat,
		.text_input    = focus && (ctx.input.keyboard.text_len || ctx.input.keyboard.modkeys & KMOD_TXT),
	};
	return ev;
}
