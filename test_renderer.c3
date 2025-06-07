import sdlrenderer::ren;
import std::io;
import std::thread;
import sdl3::sdl;

struct Viewsize @align(16) {
	int w, h;
	int ox, oy;
}

fn int main()
{
	ren::Renderer ren;
	ren.init("test window");

	ren.load_spirv_shader_from_file("rect shader", "resources/shaders/compiled/rect.vert.spv", "resources/shaders/compiled/rect.frag.spv", 0, 1);
	ren.create_pipeline("rect shader", RECT);

	for (int i = 0; i < 10; i++) {


		GPUCommandBuffer* cmdbuf = sdl::acquire_gpu_command_buffer(ren.gpu);
		GPUTexture* swapchain_texture;
		sdl::wait_and_acquire_gpu_swapchain_texture(cmdbuf, ren.win, &swapchain_texture, null, null);
		
		// FIXME: if doing damage tracking DO NOT clear the screen
		GPURenderPass* pass = sdl::begin_gpu_render_pass(cmdbuf, 
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
		ren.push_quad(100,100,100,100,0xff00ff00);
		// rect 2
		ren.push_quad(0,0,20,20,0xff0000ff);
		// rect 3
		ren.push_quad(200,300,50,50,0xffff0000);

		GPUGraphicsPipeline* p = ren.pipelines.get_from_name("rect shader").pipeline;
		if (p == null) {
			unreachable("no pipeline");
		}

		sdl::bind_gpu_graphics_pipeline(pass, p);

		Viewsize v = {.w = 640, .h = 480};
		v.ox = 50*i;
		v.oy = 50*i;
	
		sdl::push_gpu_vertex_uniform_data(cmdbuf, 1, &v, Viewsize.sizeof);

		ren.draw_quads(pass);

		sdl::end_gpu_render_pass(pass);
		sdl::submit_gpu_command_buffer(cmdbuf);

		thread::sleep_ms(250);
	}

	ren.free();
	return 0;
}