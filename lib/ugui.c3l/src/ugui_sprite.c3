module ugui;

import std::core::mem::allocator;
import std::collections::map;
import std::io;
import std::compression::qoi;

const usz SRITES_PER_ATLAS = 64;

enum SpriteType {
	SPRITE_NORMAL,
	SPRITE_SDF,
	SPRITE_MSDF,
	SPRITE_ANIMATED,
}

struct Sprite {
	Id id;
	SpriteType type;
	ushort u, v;
	ushort w, h;
}

alias SpriteMap = map::HashMap{Id, Sprite};

struct SpriteAtlas {
	Id id;
	Atlas atlas;
	SpriteMap sprites;
	bool should_update;
}

struct ElemSprite {
	Id id;
}

// name: some examples are "icons" or "images"
fn void? SpriteAtlas.init(&this, String name, AtlasType type, ushort width, ushort height)
{
	// FIXME: for now only R8G8B8A8 format is supported
	if (type != ATLAS_R8G8B8A8) {
		return INVALID_TYPE?;
	}

	this.id = name.hash();
	this.atlas.new(this.id, AtlasType.ATLAS_R8G8B8A8, width, height)!;
	this.sprites.init(allocator::heap(), capacity: SRITES_PER_ATLAS);
	this.should_update = false;
}

fn void? SpriteAtlas.free(&this)
{
	this.atlas.free();
	this.sprites.free();
}

// FIXME: this should throw an error when a different pixel format than the atlas' is used
//        or convert from the source's pixel format to the atlas'
fn Sprite*? SpriteAtlas.insert(&this, String name, SpriteType type, char[] pixels, ushort w, ushort h, ushort stride)
{
	Sprite s;
	s.id = name.hash();
	s.type = type;
	Point uv = this.atlas.place(pixels, w, h, stride)!;
	s.w = w;
	s.h = h;
	s.u = uv.x;
	s.v = uv.y;
	this.sprites.set(s.id, s);
	this.should_update = true;
	return this.sprites.get_ref(s.id);
}

fn Sprite*? SpriteAtlas.get(&this, String name)
{
	Id id = name.hash();
	return this.sprites.get_ref(id);
}

fn Sprite*? SpriteAtlas.get_by_id(&this, Id id)
{
	return this.sprites.get_ref(id);
}

macro Rect Sprite.rect(s) => {0,0,s.w,s.h};
macro Rect Sprite.uv(s) => {s.u,s.v,s.w,s.h};

fn void? Ctx.sprite_atlas_create(&ctx, String name, AtlasType type, ushort w, ushort h)
{
	ctx.sprite_atlas.init(name, type, w, h)!;
}

fn Id Ctx.get_sprite_atlas_id(&ctx, String name)
{
	return name.hash();
}

fn void? Ctx.import_sprite_memory(&ctx, String name, char[] pixels, ushort w, ushort h, ushort stride, SpriteType type = SPRITE_NORMAL)
{
	ctx.sprite_atlas.insert(name, type, pixels, w, h, stride)!;
}

fn void? Ctx.import_sprite_file_qoi(&ctx, String name, String path, SpriteType type = SPRITE_NORMAL)
{
	QOIDesc desc;

	char[] pixels = qoi::read(allocator::heap(), path, &desc, QOIChannels.RGBA)!;
	defer mem::free(pixels);

	ctx.sprite_atlas.insert(name, type, pixels, (ushort)desc.width, (ushort)desc.height, (ushort)desc.width)!;
}


macro Ctx.sprite(&ctx, String name, Point off = {0,0}, ...)
	=> ctx.sprite_id(@compute_id($vasplat), name, off);
fn void? Ctx.sprite_id(&ctx, Id id, String name, Point off)
{
	id = ctx.gen_id(id)!;

	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_SPRITE)!;

	Style* style = ctx.styles.get_style(@str_hash("sprite"));
	Sprite* sprite = ctx.sprite_atlas.get(name)!;

	Rect uv = { sprite.u, sprite.v, sprite.w, sprite.h };
	Rect bounds = { 0, 0, sprite.w, sprite.h };

	elem.bounds = ctx.layout_element(parent, bounds.off(off), style);
	elem.sprite.id = ctx.get_sprite_atlas_id(name);

	// if the bounds are null the element is outside the div view,
	//  no interaction should occur so just return
	if (elem.bounds.is_null()) return;

	Id tex_id = ctx.sprite_atlas.id;

	return ctx.push_sprite(elem.bounds, uv, tex_id, parent.div.z_index)!;
}

fn void? Ctx.draw_sprite_raw(&ctx, String name, Rect bounds, bool center = false)
{
	Elem *parent = ctx.get_parent()!;
	Sprite* sprite = ctx.sprite_atlas.get(name)!;
	Id tex_id = ctx.sprite_atlas.id;
	
	if (center) {
		Point off = {.x = (bounds.w - sprite.w) / 2, .y = (bounds.h - sprite.h) / 2};
		bounds = bounds.off(off);
	}
	
	return ctx.push_sprite(bounds, sprite.uv(), tex_id, parent.div.z_index, type: sprite.type)!;
}
