module ugui;

import std::io;

fault UgAtlasError {
	CANNOT_PLACE,
	INVALID_TYPE,
}

enum AtlasType {
	ATLAS_GRAYSCALE,
	ATLAS_R8G8B8A8,
}

// black and white atlas
struct Atlas {
	AtlasType type;
	Id id;

	ushort width, height;
	char[] buffer;

	Point row;
	ushort row_h;
}

// bytes per pixel
macro usz AtlasType.bpp(type)
{
	switch (type) {
	case ATLAS_GRAYSCALE: return 1;
	case ATLAS_R8G8B8A8: return 4;
	}
}

fn void! Atlas.new(&atlas, Id id, AtlasType type, ushort width, ushort height)
{
	atlas.id = id;
	atlas.type = type;
	atlas.width = width;
	atlas.height = height;

	atlas.buffer = mem::new_array(char, (usz)atlas.width*atlas.height*type.bpp());
}

fn void Atlas.free(&atlas)
{
	free(atlas.buffer);
}


/*
 * pixels -> +--------------+-----+
 *           |              |     | h
 *           |              |     | e
 *           |              |     | i
 *           |              |     | g
 *           |              |     | h
 *           |              |     | t
 *           +--------------+-----+
 *           |<--- width -->|
 *           |<----- stride ----->|
 * bytes per pixels are inferred and have to be the same
 * as the atlas type
 */
// place a rect inside the atlas
// uses a row first algorithm
// TODO: use a skyline algorithm https://jvernay.fr/en/blog/skyline-2d-packer/implementation/
fn Point! Atlas.place(&atlas, char[] pixels, ushort w, ushort h, ushort stride)
{
	Point p;

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

	usz bpp = atlas.type.bpp();
	for (usz y = 0; y < h; y++) {
		for (usz x = 0; x < w; x++) {
			char[] buf = atlas.buffer[(usz)(p.y+y)*atlas.width*bpp + (p.x+x)*bpp ..];
			char[] pix = pixels[(usz)y*stride*bpp + x*bpp ..];

			buf[0..bpp-1] = pix[0..bpp-1];
		}
	}

	atlas.row.x += w;
	if (h > atlas.row_h) {
		atlas.row_h = h;
	}

	return p;
}
