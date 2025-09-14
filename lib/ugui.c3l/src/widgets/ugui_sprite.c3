module ugui;

struct ElemSprite {
	Id id;
}

macro Ctx.sprite(&ctx, String name, ...)
	=> ctx.sprite_id(@compute_id($vasplat), name);
fn void? Ctx.sprite_id(&ctx, Id id, String name)
{
	id = ctx.gen_id(id)!;
	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_SPRITE)!;

	Style* style = ctx.styles.get_style(@str_hash("sprite"));
	Sprite* sprite = ctx.sprite_atlas.get(name)!;
	elem.sprite.id = ctx.get_sprite_atlas_id(name);

	elem.layout.w = elem.layout.children.w = @exact(sprite.w);
	elem.layout.h = elem.layout.children.h = @exact(sprite.h);

	update_parent_size(elem, parent);

	Id tex_id = ctx.sprite_atlas.id;
	return ctx.push_sprite(elem.bounds, sprite.uv(), tex_id, parent.div.z_index, type: sprite.type)!;
}
