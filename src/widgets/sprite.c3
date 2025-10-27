module ugui;

struct ElemSprite {
	Id id;
}

macro Ctx.sprite(&ctx, String name, short size = 0, ...)
	=> ctx.sprite_id(@compute_id($vasplat), name, size);
fn void? Ctx.sprite_id(&ctx, Id id, String name, short size = 0)
{
	id = ctx.gen_id(id)!;
	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_SPRITE)!.unpack(&elem, &parent);

	Style* style = ctx.styles.get_style(@str_hash("sprite"));
	Sprite* sprite = ctx.sprite_atlas.get(name)!;
	elem.sprite.id = ctx.get_sprite_atlas_id(name);

	// scale the sprite so that the biggest dimension becomes "size"
	short width = sprite.w;
	short height = sprite.h;
	if (size > 0) {
		if (sprite.w >= sprite.h) {
			height = (short)(size * (float)height/width);
			width = size;
		} else {
			width = (short)(size * (float)width/height);
			height = size;
		}
	}

	elem.layout.w = elem.layout.children.w = @exact(width);
	elem.layout.h = elem.layout.children.h = @exact(height);
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	Id tex_id = ctx.sprite_atlas.id;
	Rect content_bounds = elem.bounds.pad(elem.layout.content_offset);
	return ctx.push_sprite(content_bounds, sprite.uv(), tex_id, parent.z_index, type: sprite.type)!;
}
