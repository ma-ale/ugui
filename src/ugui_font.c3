module ugui;

import schrift;

struct Font @private {
	schrift::Sft sft;
	String path;
}

fn void! Ctx.font_load(&ctx, String path)
{

}

fn void Ctx.font_free(&ctx)
{

}
