#ifndef _UG_DEF_STYLE_H
#define _UG_DEF_STYLE_H

#include "ugui.h"

#define SZ_INT(x)            x.size.i

static const ug_style_t default_style = {
	.color  = { 
		.bg   = RGB_FORMAT(0x131313),
		.fg   = RGB_FORMAT(0xffffff),
	},
	.margin = SIZE_PX(3),
	.border = {
		.color = RGB_FORMAT(0xf50a00),
		.size  = SIZE_PX(10),
	},
	.title = {
		.color = {
			.bg = RGB_FORMAT(0xbbbbbb),
			.fg = RGB_FORMAT(0xffff00),
		},
		.height    = SIZE_PX(20),
		.font_size = SIZE_PX(14),
	},
	.btn = {
		.color = {
			.act = RGB_FORMAT(0x440044),
			.bg  = RGB_FORMAT(0x006600),
			.fg  = RGB_FORMAT(0xffff00),
			.sel = RGB_FORMAT(0x0a0aff),
			.br  = RGB_FORMAT(0xff00ff),
		},
		.font_size = SIZE_PX(10),
		.border    = SIZE_PX(5),
	},
};


#endif
