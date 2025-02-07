import std::io;
import vtree;
import cache;
import ugui;
import raylib5::rl;
import std::time;
import std::collections::ringbuffer;
import std::core::string;

def Times = ringbuffer::RingBuffer(<time::NanoDuration, 128>);

fn void Times.print_stats(&times)
{
	time::NanoDuration min, max, avg, x;
	min = times.get(0);
	for (usz i = 0; i < times.written; i++) {
		x = times.get(i);
		if (x < min) { min = x; }
		if (x > max) { max = x; }
		avg += x;
	}
	avg = (NanoDuration)((ulong)avg/128.0);

	io::printfn("min=%s, max=%s, avg=%s", min, max, avg);
}

struct TimeStats {
	time::NanoDuration min, max, avg;
}

fn TimeStats Times.get_stats(&times)
{
	time::NanoDuration min, max, avg, x;
	min = times.get(0);
	for (usz i = 0; i < times.written; i++) {
		x = times.get(i);
		if (x < min) { min = x; }
		if (x > max) { max = x; }
		avg += x;
	}
	avg = (NanoDuration)((ulong)avg/128.0);

	return TimeStats{.min = min, .max = max, .avg = avg};
}


const ZString MSDF_FS = `
#version 330

in vec2 fragTexCoord;
out vec4 fragColor;
uniform sampler2D texture0;
uniform vec4 colDiffuse;

const float pxRange = 4.0f;

float screenPxRange() {
    vec2 unitRange = vec2(pxRange)/vec2(textureSize(texture0, 0));
    vec2 screenTexSize = vec2(1.0)/fwidth(fragTexCoord);
    return max(0.5*dot(unitRange, screenTexSize), 1.0);
}

float median(float r, float g, float b) {
	return max(min(r, g), min(max(r, g), b));
}

void main() {
	vec3 msd = texture(texture0, fragTexCoord).rgb;
	float sd = median(msd.r, msd.g, msd.b);
	float screenPxDistance = screenPxRange()*(sd - 0.5);
	float opacity = clamp(screenPxDistance + 0.5, 0.0, 1.0);
	fragColor = colDiffuse * opacity;
}
`;

const ZString FONT_FS = `
#version 330

// Input vertex attributes (from vertex shader)
in vec2 fragTexCoord;
in vec4 fragColor;

// Input uniform values
uniform sampler2D texture0;
uniform vec4 colDiffuse;

// Output fragment color
out vec4 finalColor;

void main()
{
    vec4 alpha = texture(texture0, fragTexCoord);
    finalColor = colDiffuse*fragColor;
    finalColor.a *= alpha.r;
}
`;

// SDF based rect rendering
const ZString RECT_FS = `
#version 330

in vec2 fragTexCoord;
in vec4 fragColor;
out vec4 finalColor;

uniform float radius;
uniform float border;
uniform vec2  size;

void main()
{

}
`;

macro rl::Color ugui::Color.conv(color)
{
	return rl::Color{.r = color.r, .g = color.g, .b = color.b, .a = color.a};
}

macro rl::Rectangle Rect.conv(rect)
{
	return rl::Rectangle{.x = rect.x, .y = rect.y, .width = rect.w, .height = rect.h};
}

fn int main(String[] args)
{
	ugui::Ctx ui;
	ui.init()!!;
	defer ui.free();

	ui.load_font("font1", "resources/hack-nerd.ttf", 16)!!;
	ui.sprite_atlas_create("icons", AtlasType.ATLAS_R8G8B8A8, 512, 512)!!;
	ui.import_sprite_file_qoi("tux", "resources/tux.qoi")!!;
	ui.import_sprite_file_qoi("tick", "resources/tick_sdf.qoi", SpriteType.SPRITE_MSDF)!!;

	short width = 800;
	short height = 450;
	rl::setConfigFlags(rl::FLAG_WINDOW_RESIZABLE);
	rl::initWindow(width, height, "Ugui Test");
	ui.input_window_size(width, height)!!;
	rl::setTargetFPS(60);
	rl::enableEventWaiting();

	isz frame;
	bool toggle = true;
	time::Clock clock;
	Times ui_times;
	Times draw_times;

	// font stuff
	rl::Shader font_shader = rl::loadShaderFromMemory(null, FONT_FS);
	rl::Image font_atlas;
	rl::Texture2D font_texture;
	ugui::Id font_id = ui.get_font_id("font1");

	// sprite stuff
	rl::Shader msdf_shader = rl::loadShaderFromMemory(null, MSDF_FS);
	rl::Image sprite_atlas;
	rl::Texture2D sprite_texture;
	ugui::Id sprite_id = ui.get_sprite_atlas_id("icons");

	// Main loop
	while (!rl::windowShouldClose()) {
		clock.mark();

		ugui::ModKeys mod;
		mod.rctrl = rl::isKeyDown(rl::KEY_RIGHT_CONTROL);
		mod.lctrl = rl::isKeyDown(rl::KEY_LEFT_CONTROL);
		ui.input_mod_keys(mod);

		for (rl::KeyboardKey key; (key = (KeyboardKey)rl::getKeyPressed()) != 0;) {
			ZString kname = rl::getKeyName(key);
			if (kname == null) continue;
			ui.input_text_unicode(kname.str_view());
		}


		/* Start Input Handling */
		if (rl::isWindowResized()) {
			width  = (short)rl::getScreenWidth();
			height = (short)rl::getScreenHeight();
			ui.input_window_size(width, height)!!;
		}

		ui.input_changefocus(rl::isWindowFocused());

		rl::Vector2 mpos = rl::getMousePosition();
		ui.input_mouse_abs((short)mpos.x, (short)mpos.y);
		rl::Vector2 mwheel = rl::getMouseWheelMoveV();
		ui.input_mouse_wheel((short)mwheel.x, (short)mwheel.y);

		ugui::MouseButtons buttons = {
			.btn_left = rl::isMouseButtonDown(rl::MouseButton.LEFT),
			.btn_right = rl::isMouseButtonDown(rl::MouseButton.RIGHT),
			.btn_middle = rl::isMouseButtonDown(rl::MouseButton.MIDDLE),
		};
		ui.input_mouse_button(buttons);
		/* End Input Handling */

		/* Start UI Handling */
		ui.frame_begin()!!;

		if (ui.check_key_combo(ugui::KMOD_CTRL, "q")) break;

		ui.div_begin("main", Rect{.w=-100})!!;
		{|
			ui.layout_set_column()!!;
			if (ui.button("button0", Rect{0,0,30,30}, toggle)!!.mouse_press) {
				io::printn("press button0");
				toggle = !toggle;
			}
			//ui.layout_next_column()!!;
			if (ui.button("button1", Rect{0,0,30,30})!!.mouse_press) {
				io::printn("press button1");
			}
			//ui.layout_next_column()!!;
			if (ui.button("button2", Rect{0,0,30,30})!!.mouse_release) {
				io::printn("release button2");
			}

			ui.layout_set_row()!!;
			ui.layout_next_row()!!;
			static float rf, gf, bf, af;
			ui.slider_ver("slider_r", Rect{0,0,30,100}, &rf)!!;
			ui.slider_ver("slider_g", Rect{0,0,30,100}, &gf)!!;
			ui.slider_ver("slider_b", Rect{0,0,30,100}, &bf)!!;
			ui.slider_ver("slider_a", Rect{0,0,30,100}, &af)!!;

			ui.layout_next_column()!!;
			ui.text_unbounded("text1", "Ciao Mamma\nAbilità ⚡\n'\udb80\udd2c'")!!;

			ui.layout_next_column()!!;
			ui.button_label("Continua!")!!;

			ui.layout_next_row()!!;
			static bool check;
			ui.checkbox("check1", "", Point{}, &check, "tick")!!;
			ui.toggle("toggle1", "", Point{}, &toggle)!!;

/*
			ui.layout_set_column()!!;
			ui.button_label(" A ")!!;
			ui.button_label(" B ")!!;
			ui.layout_next_column()!!;
			ui.button_label(" C ")!!;
			ui.button_label(" D ")!!;
			ui.layout_next_row()!!;
			ui.button_label(" E ")!!;
*/
		|};
		ui.draw_sprite("sprite1", "tux")!!;
		ui.div_end()!!;

		ui.div_begin("second", ugui::DIV_FILL, scroll_x: true, scroll_y: true)!!;
		{|
			ui.layout_set_column()!!;
			static float slider2 = 0.5;
			if (ui.slider_ver("slider", Rect{0,0,30,100}, &slider2)!!.update) {
				io::printfn("other slider: %f", slider2);
			}
			ui.button("button0", Rect{0,0,50,50})!!;
			ui.button("button1", Rect{0,0,50,50})!!;
			ui.button("button2", Rect{0,0,50,50})!!;
			ui.button("button3", Rect{0,0,50,50})!!;
			if (toggle) {
				ui.button("button4", Rect{0,0,50,50})!!;
				ui.button("button5", Rect{0,0,50,50})!!;
				ui.button("button6", Rect{0,0,50,50})!!;
				ui.button("button7", Rect{0,0,50,50})!!;
			}
			ui.layout_next_column()!!;
			ui.layout_set_row()!!;
			static float f1, f2;
			ui.slider_hor("hs1", Rect{0,0,100,30}, &f1)!!;
			ui.slider_hor("hs2", Rect{0,0,100,30}, &f2)!!;
		|};
		ui.div_end()!!;

		// Timings counter
		TimeStats dts = draw_times.get_stats();
		TimeStats uts = ui_times.get_stats();

		ui.layout_set_floating()!!;
		ui.div_begin("fps", Rect{0, ui.height-100, -300, 100})!!;
		{|
			ui.layout_set_column()!!;
			ui.text_unbounded("draw times", string::tformat("ui avg: %s\ndraw avg: %s\nTOT: %s", uts.avg, dts.avg, uts.avg+dts.avg))!!;
			ui.text_unbounded("ui text input", (String)ui.input.keyboard.text[..])!!;
		|};
		ui.div_end()!!;

		ui.frame_end()!!;
		/* End UI Handling */
		ui_times.push(clock.mark());
		//ui_times.print_stats();

		/* Start UI Drawing */
		rl::beginDrawing();
		// ClearBackground(BLACK);

		for (Cmd* cmd; (cmd = ui.cmd_queue.dequeue() ?? null) != null;) {
			switch (cmd.type) {
			case CmdType.CMD_RECT:
				Rect r = cmd.rect.rect;
				float rad = cmd.rect.radius;
				// for some weird-ass reason the straight forward inverse formula does not work
				float roundness = r.w > r.h ? (2.1f*rad)/(float)r.h : (2.1f*rad)/(float)r.w;
				rl::drawRectangleRounded(cmd.rect.rect.conv(), roundness, 0, cmd.rect.color.conv());
			case CmdType.CMD_UPDATE_ATLAS:
				if (cmd.update_atlas.id == font_id) {
					//rl::unload_image(font_atlas);
					font_atlas.data = cmd.update_atlas.raw_buffer;
					font_atlas.width = cmd.update_atlas.width;
					font_atlas.height = cmd.update_atlas.height;
					font_atlas.mipmaps = 1;
					font_atlas.format = rl::PixelFormat.UNCOMPRESSED_GRAYSCALE;
					if (rl::isTextureValid(font_texture)) {
						rl::unloadTexture(font_texture);
					}
					font_texture = rl::loadTextureFromImage(font_atlas);
				} else if (cmd.update_atlas.id == sprite_id) {
					sprite_atlas.data = cmd.update_atlas.raw_buffer;
					sprite_atlas.width = cmd.update_atlas.width;
					sprite_atlas.height = cmd.update_atlas.height;
					sprite_atlas.mipmaps = 1;
					sprite_atlas.format = rl::PixelFormat.UNCOMPRESSED_R8G8B8A8;
					if (rl::isTextureValid(sprite_texture)) {
						rl::unloadTexture(sprite_texture);
					}
					sprite_texture = rl::loadTextureFromImage(sprite_atlas);
				}
			case CmdType.CMD_SPRITE:
				if (cmd.sprite.texture_id == font_id) {
					rl::Vector2 position = {
						.x = cmd.sprite.rect.x,
						.y = cmd.sprite.rect.y,
					};
					rl::beginShaderMode(font_shader);
					rl::drawTextureRec(font_texture, cmd.sprite.texture_rect.conv(), position, cmd.sprite.hue.conv());
					rl::endShaderMode();
				} else if (cmd.sprite.texture_id == sprite_id) {
					// FIXME: THIS CODE IS SHIT, REAL DOO DOO
					{|
					if (cmd.sprite.type == SpriteType.SPRITE_MSDF) {
						rl::beginShaderMode(msdf_shader);
						defer rl::endShaderMode();
						rl::drawTexturePro(sprite_texture, cmd.sprite.texture_rect.conv(), cmd.sprite.rect.conv(), rl::Vector2{0.0f, 0.0f}, 0.0f, cmd.sprite.hue.conv());
					} else {
						rl::drawTexturePro(sprite_texture, cmd.sprite.texture_rect.conv(), cmd.sprite.rect.conv(), rl::Vector2{0.0f, 0.0f}, 0.0f, cmd.sprite.hue.conv());
					}
					|};
				} else {
					io::printfn("unknown texture id: %d", cmd.sprite.texture_id);
				}
			case CmdType.CMD_SCISSOR:
				if (cmd.scissor.rect.w == 0 && cmd.scissor.rect.h == 0) {
					rl::endScissorMode();
				} else {
					rl::beginScissorMode(cmd.scissor.rect.x, cmd.scissor.rect.y, cmd.scissor.rect.w, cmd.scissor.rect.h);
				}
			default:
				io::printfn("Unknown cmd type: %s", cmd.type);
			}
		}
		draw_times.push(clock.mark());
		//draw_times.print_stats();
		rl::endDrawing();
		/* End Drawing */
	}

	rl::closeWindow();

	return 0;
}
