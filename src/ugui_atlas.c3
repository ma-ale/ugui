module ugui;

import std::core::mem;
import std::math::random;

random::SimpleRandom atlas_seed;

fault UgAtlasError {
	CANNOT_PLACE,
	INVALID_FORMAT,
	MISSING_ATLAS,
}

enum AtlasFormat {
	ATLAS_GRAYSCALE,
	ATLAS_ALPHA,
}

// black and white atlas
struct Atlas {
	AtlasFormat format;
	Id id;
	ushort width, height;
	char[] buffer;

	Point row;
	ushort row_h;
}

// FIXME: allocate atlases dynamically
fn void! Ctx.init_atlases(&ctx)
{
	atlas_seed.set_seed("ciao mamma");
	ctx.atlas = mem::new_array(Atlas, MAX_ATLAS);
}

fn void Ctx.free_atlases(&ctx)
{
	foreach (a: ctx.atlas) {
		a.free();
	}
	mem::free(ctx.atlas);
}

// FIXME: this could be slow
fn Atlas*! Ctx.get_atlas(&ctx, Id id)
{
	foreach (i, a: ctx.atlas) {
		if (a.id == id) {
			return &ctx.atlas[i];
		}
	}
	return UgAtlasError.MISSING_ATLAS?;
}

// TODO: use the same allocator as all the other parts of the code
fn Atlas*! Ctx.request_new_atlas(&ctx, AtlasFormat format, Id *rid, ushort width, ushort height)
{
	usz idx;
	bool free = false;
	for (; idx < ctx.atlas.len; idx++) {
		if (ctx.atlas[idx].id == 0) {
			free = true;
			break;
		}
	}

	if (free) {
		*rid = ctx.unique_atlas_id();
		ctx.atlas[idx].new(format, *rid, width, height)!;
		return &ctx.atlas[idx];
	} else {
		// TODO: reallocate the atlas vector
		return UgAtlasError.MISSING_ATLAS?;
	}
}

// FIXME: WTF
fn Id Ctx.unique_atlas_id(&ctx) {
	Id id = atlas_seed.next_long();
	bool ok = true;
	foreach (a: ctx.atlas) {
		if (a.id == id) {
			ok = false;
		}
	}
	return ok ? id : ctx.unique_atlas_id();
}

fn void Ctx.discard_atlas(&ctx, Id id)
{
	foreach (&a: ctx.atlas) {
		if (a.id == id) {
			a.free();
			*a = Atlas{};
		}
	}
}

// Try to place a sprite into an atlas of the correct type and return it's id
// new_width and new_height are used in case a new atlas has to be requested, in that
// case they are used as width and height for the new atlas
// FIXME: maybe there has to be a default value
fn Id! Ctx.place_sprite(&ctx, Point* uv, AtlasFormat format, char[] pixels, ushort w, ushort h, ushort new_width, ushort new_height)
{
	// try to place the sprite into an existing atlas
	foreach (&a: ctx.atlas) {
		if (a.id != 0 && a.format == format) {
			Point! ouv = a.place(pixels, w, h);
			if (catch ouv) {
				continue;
			}
			*uv = ouv;
			return a.id;
		}
	}

	// fail... try to request a new atlas and place it there
	Id id;
	Atlas* atlas = ctx.request_new_atlas(format, &id, new_width, new_height)!;
	*uv = atlas.place(pixels, w, h)!;
	return id;
}

fn void! Atlas.new(&atlas, AtlasFormat format, Id id, ushort width, ushort height)
{
	atlas.format = format;
	atlas.id = id;
	atlas.width = width;
	atlas.height = height;

	usz bpp = 1;
	switch (format) {
	case ATLAS_GRAYSCALE: nextcase;
	case ATLAS_ALPHA:
		bpp = 1;
	default:
		return UgAtlasError.INVALID_FORMAT?;
	}
	usz size = ((usz)atlas.width*atlas.height) * bpp;
	atlas.buffer = mem::new_array(char, size);
}

fn void Atlas.free(&atlas)
{
	free(atlas.buffer);
}

// place a rect inside the atlas
// uses a row first algorithm
// TODO: use a skyline algorithm https://jvernay.fr/en/blog/skyline-2d-packer/implementation/
// FIXME: untested with non-1bpp buffer depths
fn Point! Atlas.place(&atlas, char[] pixels, ushort w, ushort h)
{
	Point p;

	// TODO: simplify this and use rect_collision() and such
	if (atlas.row.x + w <= atlas.width && atlas.row.y + h <= atlas.height) {
		p = atlas.row;
	} else {
		atlas.row.x = 0;
		atlas.row.y = atlas.row.y + atlas.row_h;
		atlas.row_h = 0;
		if (atlas.row.x + w <= atlas.width && atlas.row.y + h <= atlas.height) {
			p = atlas.row;
		} else {
			return UgAtlasError.CANNOT_PLACE?;
		}
	}

	for (usz y = 0; y < h; y++) {
		for (usz x = 0; x < w; x++) {
			atlas.buffer[(usz)(p.y+y)*atlas.width + (p.x+x)] = pixels[y*w + x];
		}
	}

	atlas.row.x += w;
	if (h > atlas.row_h) {
		atlas.row_h = h;
	}

	return p;
}
