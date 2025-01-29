module ugui;

import std::collections::map;
import std::io;
import mqoi;

const usz SRITES_PER_ATLAS = 64;

struct Sprite {
	Id id;
	ushort u, v;
	ushort w, h;
}

def SpriteMap = map::HashMap(<Id, Sprite>);

struct SpriteAtlas {
	Id id;
	Atlas atlas;
	SpriteMap sprites;
	bool should_update;
}


// name: some examples are "icons" or "images"
fn void! SpriteAtlas.init(&this, String name, AtlasType type, ushort width, ushort height)
{
	// FIXME: for now only RGBA32 format is supported
	if (type != ATLAS_RGBA32) {
		return UgAtlasError.INVALID_TYPE?;
	}

	this.id = name.hash();
	this.atlas.new(this.id, AtlasType.ATLAS_RGBA32, width, height)!;
	this.sprites.new_init(capacity: SRITES_PER_ATLAS);
	this.should_update = false;
}

fn void! SpriteAtlas.free(&this)
{
	this.atlas.free();
	this.sprites.free();
}

// FIXME: this should throw an error when a different pixel format than the atlas' is used
fn Sprite*! SpriteAtlas.insert(&this, String name, char[] pixels, ushort w, ushort h, ushort stride)
{
	Sprite s;
	s.id = name.hash();
	Point uv = this.atlas.place(pixels, w, h, stride)!;
	s.w = w;
	s.h = h;
	s.u = uv.x;
	s.v = uv.y;
	this.sprites.set(s.id, s);
	this.should_update = true;
	return this.sprites.get_ref(s.id);
}

fn Sprite*! SpriteAtlas.get(&this, String name)
{
	Id id = name.hash();
	return this.sprites.get_ref(id);
}

fn Sprite*! SpriteAtlas.get_by_id(&this, Id id)
{
	return this.sprites.get_ref(id);
}

fn void! Ctx.sprite_atlas_create(&ctx, String name, AtlasType type, ushort w, ushort h)
{
	ctx.sprite_atlas.init(name, type, w, h)!;
}

fn Id Ctx.get_sprite_atlas_id(&ctx, String name)
{
	return name.hash();
}

fn void! Ctx.import_sprite_memory(&ctx, String name, char[] pixels, ushort w, ushort h, ushort stride)
{
	ctx.sprite_atlas.insert(name, pixels, w, h, stride)!;
}

fn void! Ctx.import_sprite_file_qoi(&ctx, String name, String path)
{
	mqoi::Desc image_desc;
	uint w, h;

	File file = file::open(path, "rb")!;
	defer (void) file.close();

	while (!mqoi::desc_done(&image_desc)) {
		mqoi::desc_push(&image_desc, file.read_byte()!);
	}
	if (mqoi::desc_verify(&image_desc, &w, &h) != 0) {
		return IoError.FILE_NOT_VALID?;
	}

	mqoi::Dec dec;
	mqoi::Rgba* px;

	usz idx;
	char[] pixels = mem::new_array(char, (usz)w*h*4);
	defer mem::free(pixels);

	mqoi::dec_init(&dec, w*h);
	while (!mqoi::dec_done(&dec)) {
		mqoi::dec_push(&dec, file.read_byte()!);

		while ((px = mqoi::dec_pop(&dec)) != null) {
			pixels[idx..idx+3] = px.value;
			idx += 4;
		}
	}

	ctx.sprite_atlas.insert(name, pixels, (ushort)w, (ushort)h, (ushort)w)!;
}

// FIXME: test function, very different from every other function here
fn void! Ctx.draw_sprite(&ctx, String name)
{
	Sprite* sprite = ctx.sprite_atlas.get(name)!;
	Rect bounds = { 100, 100, sprite.w, sprite.h };
	Rect uv = { sprite.u, sprite.v, sprite.w, sprite.h };
	Id tex_id = ctx.sprite_atlas.id;

	return ctx.push_sprite(bounds, uv, tex_id)!;
}
