import sdlrenderer::ren;
import std::io;
import std::thread;
import sdl3::sdl;
import std::compression::qoi;
import std::core::mem::allocator;

struct Viewsize @align(16) {
	int w, h;
	int ox, oy;
}

fn int main()
{
	ren::Renderer ren;
	ren.init("test window");

	// TODO: these could be the same function
	ren.load_spirv_shader_from_file("rect shader", "resources/shaders/compiled/rect.vert.spv", "resources/shaders/compiled/rect.frag.spv", 0, 1);
	ren.create_pipeline("rect shader", RECT);

	// load the tux qoi image
	QOIDesc img_desc;
	char[] img_pixels = qoi::read(allocator::temp(), "resources/tux.qoi", &img_desc)!!;
	// and put it in a texture
	ren.new_texture("tux", FULL_COLOR, img_pixels, img_desc.width, img_desc.height);
	// create a new pipeline to use the texture
	ren.load_spirv_shader_from_file("sprite shader", "resources/shaders/compiled/sprite.vert.spv", "resources/shaders/compiled/sprite.frag.spv", 1, 1);
	ren.create_pipeline("sprite shader", SPRITE);

	for (int i = 0; i < 20; i++) {
		GPUCommandBuffer* cmdbuf = sdl::acquire_gpu_command_buffer(ren.gpu);
		GPUTexture* swapchain_texture;
		sdl::wait_and_acquire_gpu_swapchain_texture(cmdbuf, ren.win, &swapchain_texture, null, null);

		GPURenderPass* pass;
		GPUGraphicsPipeline* p;
		Viewsize v = {.w = 640, .h = 480};

		// Colored Rectangles Render Pass
		// FIXME: if doing damage tracking DO NOT clear the screen
		pass = sdl::begin_gpu_render_pass(cmdbuf, 
			&&(GPUColorTargetInfo){
				.texture = swapchain_texture,
				.mip_level = 0,
				.layer_or_depth_plane = 0,
				.clear_color = {.r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0},
				.load_op = GPU_LOADOP_CLEAR, // clear the screen at the start of the render pass
				.store_op = GPU_STOREOP_STORE,
				.resolve_texture = null,
				.resolve_mip_level = 0,
				.resolve_layer = 0,
				.cycle = false,
				.cycle_resolve_texture = false
			},
			1,
			null // huh
		);

		if (pass == null) {
			unreachable("render pass creation went wrong: %s", sdl::get_error());
		}

		// rect 1
		ren.push_quad(100,100,100,100,0xff00ff00, 20);
		// rect 2
		ren.push_quad(0,0,20,20,0xff0000ff);
		// rect 3
		ren.push_quad(200,300,50,50,0xffff0000);

		p = ren.pipelines.get_from_name("rect shader").pipeline;
		if (p == null) {
			unreachable("no pipeline");
		}

		sdl::bind_gpu_graphics_pipeline(pass, p);

		v.ox = 10*i;
		v.oy = 10*i;	
		sdl::push_gpu_vertex_uniform_data(cmdbuf, 1, &v, Viewsize.sizeof);

		ren.draw_quads(pass);

		sdl::end_gpu_render_pass(pass);
		// End Rectangle Render Pass


		// Textured Rectangles Render Pass
			pass = sdl::begin_gpu_render_pass(cmdbuf, 
			&&(GPUColorTargetInfo){
				.texture = swapchain_texture,
				.mip_level = 0,
				.layer_or_depth_plane = 0,
				.clear_color = {.r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0},
				.load_op = GPU_LOADOP_DONT_CARE, // clear the screen at the start of the render pass
				.store_op = GPU_STOREOP_STORE,
				.resolve_texture = null,
				.resolve_mip_level = 0,
				.resolve_layer = 0,
				.cycle = false,
				.cycle_resolve_texture = false
			},
			1,
			null // huh
		);

		if (pass == null) {
			unreachable("render pass creation went wrong: %s", sdl::get_error());
		}

		p = ren.pipelines.get_from_name("sprite shader").pipeline;
		if (p == null) {
			unreachable("no pipeline");
		}

		sdl::bind_gpu_graphics_pipeline(pass, p);
		// in this case it is not an offset but the texture size in pixels
		v.ox = 54;
		v.oy = 64;
		sdl::push_gpu_vertex_uniform_data(cmdbuf, 1, &v, Viewsize.sizeof);

		// bind the pipeline's sampler
		ren::Texture* tx = ren.textures.get_from_name("tux");
		sdl::bind_gpu_fragment_samplers(pass, 0, 
			(GPUTextureSamplerBinding[]){{.texture = tx.texture, .sampler = tx.sampler}}, 1
		);

		// tux
		ren.push_sprite(300, 0, 54, 64, 0, 0);

		ren.draw_quads(pass);

		sdl::end_gpu_render_pass(pass);
		// End Textured Rectangle Render Pass

		sdl::submit_gpu_command_buffer(cmdbuf);

		ren.reset_quads();
		thread::sleep_ms(250);
	}

	ren.free();
	return 0;
}