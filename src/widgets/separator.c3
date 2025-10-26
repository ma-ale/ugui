module ugui;


macro Ctx.separator(&ctx, Size width, Size height, ...)
	=> ctx.separator_id(@compute_id($vasplat), width, height);
fn void? Ctx.separator_id(&ctx, Id id, Size width, Size height)
{
	id = ctx.gen_id(id)!;
	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_NONE)!.unpack(&elem, &parent);

	elem.layout.w = width;
	elem.layout.h = height;

	update_parent_size(elem, parent);
}


macro Ctx.hor_line(&ctx, ...)
	=> ctx.hor_line_id(@compute_id($vasplat));
fn void? Ctx.hor_line_id(&ctx, Id id)
{
	id = ctx.gen_id(id)!;
	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_NONE)!.unpack(&elem, &parent);
	Style* style = ctx.styles.get_style(@str_hash("separator"));

	elem.layout.w = @grow();
	elem.layout.h = @exact(style.size);
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	Rect r = elem.bounds.pad(elem.layout.content_offset);
	ctx.push_rect(r, elem.z_index, style)!;
}


macro Ctx.ver_line(&ctx, ...)
	=> ctx.ver_line_id(@compute_id($vasplat));
fn void? Ctx.ver_line_id(&ctx, Id id)
{
	id = ctx.gen_id(id)!;
	Elem* parent, elem;
	ctx.get_elem(id, ETYPE_NONE)!.unpack(&elem, &parent);
	Style* style = ctx.styles.get_style(@str_hash("separator"));

	elem.layout.w = @exact(style.size);
	elem.layout.h = @grow();
	elem.layout.content_offset = style.margin + style.border + style.padding;

	update_parent_size(elem, parent);

	Rect r = elem.bounds.pad(elem.layout.content_offset);
	ctx.push_rect(r, elem.z_index, style)!;
}