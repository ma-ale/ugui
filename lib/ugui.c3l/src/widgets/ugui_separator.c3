module ugui;


macro Ctx.separator(&ctx, int width, int height, ...)
	=> ctx.separator_id(@compute_id($vasplat), width, height);
fn void? Ctx.separator_id(&ctx, Id id, int width, int height)
{
	id = ctx.gen_id(id)!;
	Elem *parent = ctx.get_parent()!;
	Elem *elem = ctx.get_elem(id, ETYPE_NONE)!;

	elem.layout.w = @exact((short)width);
	elem.layout.h = @exact((short)height);

	update_parent_size(elem, parent);
}