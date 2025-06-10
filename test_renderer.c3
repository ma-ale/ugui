import sdlrenderer::ren;
import std::io;
import std::thread;
import sdl3::sdl;
import std::compression::qoi;
import std::core::mem::allocator;

char[*] shader_rect_vert = $embed("resources/shaders/compiled/rect.vert.spv");
char[*] shader_rect_frag = $embed("resources/shaders/compiled/rect.frag.spv");

char[*] shader_sprite_vert = $embed("resources/shaders/compiled/sprite.vert.spv");
char[*] shader_sprite_frag = $embed("resources/shaders/compiled/sprite.frag.spv");

const uint WINDOW_WIDTH  = 640;
const uint WINDOW_HEIGHT = 480;


fn int main()
{
	ren::Renderer ren;
	ren.init("test window", WINDOW_WIDTH, WINDOW_HEIGHT);

	// TODO: these could be the same function
	ren.load_spirv_shader_from_mem("rect shader", &shader_rect_vert, &shader_rect_frag, 0, 0);
	ren.create_pipeline("rect shader", RECT);

	// load the tux qoi image
	QOIDesc img_desc;
	char[] img_pixels = qoi::read(allocator::temp(), "resources/tux.qoi", &img_desc)!!;
	// and put it in a texture
	ren.new_texture("tux", FULL_COLOR, img_pixels, img_desc.width, img_desc.height);
	// create a new pipeline to use the texture
	ren.load_spirv_shader_from_mem("sprite shader", &shader_sprite_vert, &shader_sprite_frag, 1, 0);
	ren.create_pipeline("sprite shader", SPRITE);


	sdl::Event e;
	bool quit = false;
	for (usz i = 0; !quit; i++) {

		if (sdl::poll_event(&e)) {
			if (e.type == EVENT_QUIT) {
				quit = true;
			}
		}

		if (i == 300) {
			io::printn("ciao!");
			img_pixels = qoi::read(allocator::temp(), "resources/tux_inv.qoi", &img_desc)!!;
			ren.update_texture("tux", img_pixels, img_desc.width, img_desc.height);
		}

		ren.begin_render(true);

		// Colored Rectangles Render Pass
		ren.start_render_pass("rect shader");

		// rect 1
		ren.push_quad(100,100,100,100,0xff00ff00, 20);
		// rect 2
		ren.push_quad(0,0,20,20,0xff0000ff);
		// rect 3
		ren.push_quad(200,300,50,50,0xffff0000);

		//ren.set_scissor(0,50,200,300);

		ren.draw_quads();

		ren.end_render_pass();
		// End Rectangle Render Pass


		// Textured Rectangles Render Pass
		ren.start_render_pass("sprite shader");
		
		// bind the pipeline's sampler
		ren.bind_texture("tux");

		// tux
		ren.push_sprite(300, 0, 54, 64, 0, 0);

		ren.reset_scissor();

		ren.draw_quads();

		ren.end_render_pass();
		// End Textured Rectangle Render Pass

		ren.end_render();
	}

	ren.free();
	return 0;
}