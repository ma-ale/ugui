module sdlrenderer::ren;

// 2D renderer for ugui, based on SDL3 using the new GPU API
// TODO: use unreachable() instead of the combo eprintfn();exit(1); since it does the same thing
//       but also adds a helpful stack trace

import std::io;
import std::core::mem;
import sdl3::sdl;
import libc;
import std::collections::list;

struct Shader {
	sdl::GPUShader* frag;
	sdl::GPUShader* vert;
	uint id;
}

struct Pipeline {
	sdl::GPUGraphicsPipeline* pipeline;
	uint id;
}

struct Texture {
	sdl::GPUTexture* texture;
	sdl::GPUSampler* sampler;
	ushort width, height;
	uint id;
}

// gpu buffer that contains a single quad
struct QuadBuffer {
	sdl::GPUBuffer* vert_buf;
	sdl::GPUBuffer* idx_buf;
	bool initialized;
}

alias ShaderList = List{Shader};
alias PipelineList = List{Pipeline};
alias TextureList = List{Texture};

struct Renderer {
	sdl::Window* win;
	sdl::GPUDevice* gpu;
	QuadBuffer quad_buffer;
	ShaderList shaders;
	PipelineList pipelines;
	TextureList textures;
}

// how each vertex is represented in the gpu
struct Vertex @packed {
	struct pos {
		float x, y;
	}
	struct uv {
		float u, v;
	}
	struct col { // FIXME: this is shit
		union {
			char r, g, b, a;
			char[4] arr;
			uint u;
		}
	}
}

struct Quad @packed {
	struct vertices {
		Vertex v1,v2,v3,v4;
	}
	struct indices {
		short i1,i2,i3,i4,i5,i6;
	}
}

const int DEBUG = 1;

fn void Renderer.init(&self, ZString title)
{
	// set wayland hint automagically
$if DEBUG == 0:
	bool has_wayland = false;
	for (int i = 0; i < sdl::get_num_video_drivers(); i++) {
		ZString driver = sdl::get_video_driver(i);
		if (driver.str_view() == "wayland") {
			has_wayland = true;
			break;
		}
	}

	if (has_wayland) {
		sdl::set_hint(sdl::HINT_VIDEO_DRIVER, "wayland");
	}
$else
	sdl::set_hint(sdl::HINT_VIDEO_DRIVER, "x11");
$endif


	sdl::set_hint(sdl::HINT_RENDER_GPU_DEBUG, "1");

	// init subsystems
	if (!sdl::init(INIT_VIDEO)) {
		io::eprintfn("sdl error: %s", sdl::get_error());
		libc::exit(1);
	}

	// create the window
	self.win = sdl::create_window(title, 640, 480, WINDOW_RESIZABLE|WINDOW_VULKAN);
	if (self.win == null) {
		io::eprintfn("sdl error: %s", sdl::get_error());
		libc::exit(1);
	}

	// get the gpu device handle
	self.gpu = sdl::create_gpu_device(GPU_SHADERFORMAT_SPIRV, true, "vulkan");
	if (self.gpu == null) {
		io::eprintfn("failed to create gpu device: %s", sdl::get_error());
		libc::exit(1);
	}

	if (!sdl::claim_window_for_gpu_device(self.gpu, self.win)) {
		io::eprintfn("failed to claim window for use with gpu: %s", sdl::get_error());
		libc::exit(1);
	}

	// initialize the quad buffer
	self.quad_buffer.vert_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_VERTEX, .size = Quad.vertices.sizeof}
	);
	if (self.quad_buffer.vert_buf == null) {
		io::eprintfn("failed to initialize quad buffer (vertex): %s", sdl::get_error());
		libc::exit(1);
	}

	self.quad_buffer.idx_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_INDEX, .size = Quad.indices.sizeof}
	);
	if (self.quad_buffer.idx_buf == null) {
		io::eprintfn("failed to initialize quad buffer (index): %s", sdl::get_error());
		libc::exit(1);
	}

	self.quad_buffer.initialized = true;
}

fn void Renderer.free(&self)
{
	foreach (&s: self.shaders) {
		sdl::release_gpu_shader(self.gpu, s.frag);
		sdl::release_gpu_shader(self.gpu, s.vert);
	}
	self.shaders.free();

	foreach (&p: self.pipelines) {
		sdl::release_gpu_graphics_pipeline(self.gpu, p.pipeline);
	}
	self.pipelines.free();

	sdl::release_window_from_gpu_device(self.gpu, self.win);
	sdl::destroy_gpu_device(self.gpu);
	sdl::destroy_window(self.win);
	sdl::quit();
}

fn void Renderer.load_spirv_shader_from_mem(&self, String name, char[] vert_code, char[] frag_code, uint textures, uint uniforms)
{
	Shader s;
	s.id = name.hash();

	if (vert_code.len == 0 || frag_code.len == 0) {
		unreachable("vertex shader and fragment shader cannot be empty");
	}

	if (vert_code.len > 0) {
		// FIXME: these should be passed by parameter and/or automatically determined by parsing
		//        the shader code
		GPUShaderCreateInfo shader_info = {
			.code = vert_code.ptr,
			.code_size = vert_code.len,
			.entrypoint = "main",
			.format = GPU_SHADERFORMAT_SPIRV,
			.stage = GPU_SHADERSTAGE_VERTEX,
			.num_samplers = 0,
			.num_uniform_buffers = uniforms,
			.num_storage_buffers = 0,
			.num_storage_textures = 0
		};

		s.vert = sdl::create_gpu_shader(self.gpu, &shader_info);
		if (s.vert == null) {
			io::eprintfn("failed to create gpu vertex shader: %s", sdl::get_error());
			libc::exit(1);
		}
	}

	if (frag_code.len > 0) {
		// FIXME: these should be passed by parameter and/or automatically determined by parsing
		//        the shader code
		GPUShaderCreateInfo shader_info = {
			.code = frag_code.ptr,
			.code_size = frag_code.len,
			.entrypoint = "main",
			.format = GPU_SHADERFORMAT_SPIRV,
			.stage = GPU_SHADERSTAGE_FRAGMENT,
			.num_samplers = textures,
			.num_uniform_buffers = 0,
			.num_storage_buffers = 0,
			.num_storage_textures = 0
		};

		s.frag = sdl::create_gpu_shader(self.gpu, &shader_info);
		if (s.frag == null) {
			io::eprintfn("failed to create gpu fragment shader: %s", sdl::get_error());
			libc::exit(1);
		}
	}

	// push the shader into the list
	self.shaders.push(s);
}

fn void Renderer.load_spirv_shader_from_file(&self, String name, String vert_path, String frag_path, uint textures, uint uniforms) 
{
	if (vert_path == "" || frag_path == "") {
		unreachable("need both a vertex shader and fragment shader path");
	}

	char[] vert_code;
	char[] frag_code;

	// create vertex shader
	if (vert_path != "") {
		vert_code = mem::new_array(char, file::get_size(vert_path)!!+1);
		file::load_buffer(vert_path, vert_code)!!;
	}

	// create fragment shader
	if (frag_path != "") {
		frag_code = mem::new_array(char, file::get_size(frag_path)!!+1);
		file::load_buffer(frag_path, frag_code)!!;
	}

	self.load_spirv_shader_from_mem(name, vert_code, frag_code, textures, uniforms);

	if (vert_code.ptr) mem::free(vert_code);
	if (frag_code.ptr) mem::free(frag_code);
}

fn Shader* ShaderList.get_from_name(&self, String name)
{
	uint id = name.hash();
	foreach(&s: self) {
		if (s.id == id) {
			return s;
		}
	}
	return null;
}

fn Pipeline* PipelineList.get_from_name(&self, String name)
{
	uint id = name.hash();
	foreach(&p: self) {
		if (p.id == id) {
			return p;
		}
	}
	return null;
}

fn Texture* TextureList.get_from_name(&self, String name)
{
	uint id = name.hash();
	foreach(&t: self) {
		if (t.id == id) {
			return t;
		}
	}
	return null;
}


// this describes what we want to draw, since for drawing different things we have to change
// the GPUPrimitiveType and GPURasterizerState for the pipeline.
enum PipelineType : (GPUPrimitiveType primitive_type, GPURasterizerState raster_state) {
	RECT   = {GPU_PRIMITIVETYPE_TRIANGLELIST, {.fill_mode = GPU_FILLMODE_FILL, .cull_mode = GPU_CULLMODE_NONE, .front_face = GPU_FRONTFACE_COUNTER_CLOCKWISE}},
	SPRITE = {GPU_PRIMITIVETYPE_TRIANGLELIST, {.fill_mode = GPU_FILLMODE_FILL, .cull_mode = GPU_CULLMODE_NONE, .front_face = GPU_FRONTFACE_COUNTER_CLOCKWISE}},
	LINE   = {GPU_PRIMITIVETYPE_LINELIST,     {.fill_mode = GPU_FILLMODE_LINE, .cull_mode = GPU_CULLMODE_NONE, .front_face = GPU_FRONTFACE_COUNTER_CLOCKWISE}},
}

// create a graphics pipeline to draw to the window using a set of vertex/fragment shaders
// the pipeline is pushed into the renderer's pipeline list and it will have the same id as
// the shader set.
fn void Renderer.create_pipeline(&self, String shader_name, PipelineType type)
{
	Shader *s = self.shaders.get_from_name(shader_name);
	if (s == null) {
		io::eprintfn("error in creating pipeline: no shader named %s", shader_name);
		libc::exit(1);
	}

	GPUGraphicsPipelineCreateInfo ci = {
		.vertex_shader = s.vert,
		.fragment_shader = s.frag,
		// This structure specifies how the vertex buffer looks in memory, what it contains
		// and what is passed where to the gpu. Each vertex has three attributes, position,
		// color and uv coordinates. Since this is a 2D pixel-based renderer the position 
		// is represented by two floats, the color as 32 bit rgba and the uv also as intgers. 
		.vertex_input_state = {
			// the description of each vertex buffer, for now I use only one buffer
			.vertex_buffer_descriptions = (GPUVertexBufferDescription[]){{
				.slot = 0,
				.pitch = Vertex.sizeof,
				.input_rate = GPU_VERTEXINPUTRATE_VERTEX,
				.instance_step_rate = 0,
			}},
			.num_vertex_buffers = 1,
			// the description of each vertex, each vertex has three properties
			.vertex_attributes = (GPUVertexAttribute[]){
				{ // at location zero there is the position of the vertex
					.location = 0,
					.buffer_slot = 0, // only one buffer so always slot zero
					.format = GPU_VERTEXELEMENTFORMAT_FLOAT2,
					.offset = Vertex.pos.offsetof,
				},
				{ // at location one there are the uv coordinates
					.location = 1,
					.buffer_slot = 0,
					.format = GPU_VERTEXELEMENTFORMAT_FLOAT2,
					.offset = Vertex.uv.offsetof,
				},
				{ // at location two there is the color
					.location = 2,
					.buffer_slot = 0,
					.format = GPU_VERTEXELEMENTFORMAT_UBYTE4, // 4x8bit unsigned rgba format
					.offset = Vertex.col.offsetof,
				}
			},
			.num_vertex_attributes = 3,
		},
		// the pipeline's primitive type and rasterizer state differs based on what needs to
		// be drawn
		.primitive_type = type.primitive_type,
		.rasterizer_state = type.raster_state,
		.multisample_state = {},  // no multisampling, all zeroes
		.depth_stencil_state = {},  // no stencil test, all zeroes
		.target_info = { // the target (texture) description
			.color_target_descriptions = (GPUColorTargetDescription[]){{
				// rendering happens to the window, so get it's format
				.format = sdl::get_gpu_swapchain_texture_format(self.gpu, self.win),
				.blend_state = {
					// alpha blending on everything
					// https://en.wikipedia.org/wiki/Alpha_compositing
					.src_color_blendfactor = GPU_BLENDFACTOR_SRC_ALPHA,
					.dst_color_blendfactor = GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
					.color_blend_op = GPU_BLENDOP_ADD,
					.src_alpha_blendfactor = GPU_BLENDFACTOR_SRC_ALPHA,
					.dst_alpha_blendfactor = GPU_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
					.alpha_blend_op = GPU_BLENDOP_ADD,
					.enable_blend = true,
					// color write mask is not enabled so all rgba channels are written to
				},
			}},
			.num_color_targets = 1,
			.depth_stencil_format = {}, // FIXME: no stencil, no depth buffering
			.has_depth_stencil_target = false,
		},
	};

	// create the pipeline and add it to the pipeline list
	Pipeline p = {
		.id = s.id,
		.pipeline = sdl::create_gpu_graphics_pipeline(self.gpu, &ci),
	};

	if (p.pipeline == null) {
		io::eprintfn("failed to create pipeline (shaders: %s, type: %s): %s", shader_name, type.nameof, sdl::get_error());
		libc::exit(1);
	}

	self.pipelines.push(p);
}

enum TextureType : (GPUTextureFormat format) {
	FULL_COLOR = GPU_TEXTUREFORMAT_R8G8B8A8_UINT,
	JUST_ALPHA = GPU_TEXTUREFORMAT_R8_UINT
} 

// create a new gpu texture from a pixel buffer, the format has to be specified
// the new texture s given an id and pushed into a texture list
fn void Renderer.new_texture(&self, String name, TextureType type, char[] pixels, ushort width, ushort height)
{
	uint id = name.hash();
	
	// the texture description
	GPUTextureCreateInfo tci = {
		.type = GPU_TEXTURETYPE_2D,
		.format = type.format,
		// all textures are used with samplers, which means read-only textures that contain data to be sampled
		.usage = GPU_TEXTUREUSAGE_SAMPLER,
		.width = width,
		.height = height,
		.layer_count_or_depth = 1,
		.num_levels = 0, // no mip maps
		// .sample_count not used since the texture is not a render target
	};

	GPUTexture* texture = sdl::create_gpu_texture(self.gpu, &tci);
	if (texture == null) {
		io::eprintfn("failed to create texture (name: %s, type: %s): %s", name, type.nameof, sdl::get_error());
		libc::exit(1);
	}

	// the sampler description, how the texture should be sampled
	GPUSamplerCreateInfo sci = {
		.min_filter = GPU_FILTER_LINEAR, // linear interpolation for textures
		.mag_filter = GPU_FILTER_LINEAR,
		.mipmap_mode = GPU_SAMPLERMIPMAPMODE_NEAREST,
		.address_mode_u = GPU_SAMPLERADDRESSMODE_REPEAT, // tiling textures
		.address_mode_v = GPU_SAMPLERADDRESSMODE_REPEAT,
		.address_mode_w = GPU_SAMPLERADDRESSMODE_REPEAT,
		// everything else is not used and not needed
	};

	GPUSampler* sampler = sdl::create_gpu_sampler(self.gpu, &sci);
	if (sampler == null) {
		io::eprintfn("failed to create sampler (texture name: %s, type: %s): %s", name, type.nameof, sdl::get_error());
		libc::exit(1);
	}

	Texture t = {
		.id = id,
		.texture = texture,
		.sampler = sampler,
	};
	self.textures.push(t);

	// upload the texture data
	self.update_texture(name, pixels, width, height);
}

fn void Renderer.update_texture(&self, String name, char[] pixels, ushort width, ushort height, ushort x = 0, ushort y = 0)
{
	Texture* t = self.textures.get_from_name(name);
	if (t == null || t.texture == null) {
		io::eprintf("failed updating texture: no texture named %s", name);
		libc::exit(1);
	}
	GPUTexture* texture = t.texture;

	// FIXME: do a better job at validating the copy
	if (x > t.width || y > t.height) {
		io::eprintf("failed updating texture: attempting to copy outside of the texture region", name);
		libc::exit(1);
	}

	// upload image data
	GPUCommandBuffer* cmdbuf = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmdbuf == null) {
		io::eprintfn("failed to upload texture data at acquiring command buffer: %s", sdl::get_error());
		libc::exit(1);
	}
	GPUCopyPass* copypass = sdl::begin_gpu_copy_pass(cmdbuf);
	if (copypass == null) {
		io::eprintfn("failed to upload texture data at beginning copy pass: %s", sdl::get_error());
		libc::exit(1);
	}

	GPUTransferBuffer* buf = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = pixels.len}
	);
	if (buf == null) {
		io::eprintfn("failed to upload texture data at creating the transfer buffer: %s", sdl::get_error());
		libc::exit(1);
	}

	char* gpu_mem = (char*)sdl::map_gpu_transfer_buffer(self.gpu, buf, false);
	if (gpu_mem == null) {
		io::eprintfn("failed to upload texture data at mapping the transfer buffer: %s", sdl::get_error());
		libc::exit(1);
	}
	// copy the data to the driver's memory
	gpu_mem[:pixels.len] = pixels[..];
	sdl::unmap_gpu_transfer_buffer(self.gpu, buf);

	// upload the data to gpu memory
	sdl::upload_to_gpu_texture(copypass,
		&&(GPUTextureTransferInfo){.transfer_buffer = buf, .offset = 0},
		&&(GPUTextureRegion){.texture = texture, .x = x, .y = y, .w = width, .h = height, .d = 1},
		false
	);

	sdl::end_gpu_copy_pass(copypass);
	if (!sdl::submit_gpu_command_buffer(cmdbuf)) {
		io::eprintfn("failed to upload texture data at command buffer submission: %s", sdl::get_error());
		libc::exit(1);
	}
	sdl::release_gpu_transfer_buffer(self.gpu, buf);
}


macro void Vertex.norm(&p, float w, float h)
{
	p.pos.x = p.pos.x * 2.0 / w - 1.0;
	p.pos.y = -(p.pos.y * 2.0 / h - 1.0);
}

// an highly inefficient way to draw a single quad, no batching, per-quad upload
fn void Renderer.draw_rect(&self, short x, short y, short w, short h, uint color, String shader_name)
{
	// upload the quad data to the gpu
	if (self.quad_buffer.initialized == false) {
		io::eprintfn("quad buffer not initialized");
		libc::exit(1);
	}

	GPUTransferBuffer* buf = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = Quad.sizeof}
	);
	if (buf == null) {
		io::eprintfn("failed to create gpu transfer buffer: %s", sdl::get_error());
		libc::exit(1);
	}

	Quad* quad = (Quad*)sdl::map_gpu_transfer_buffer(self.gpu, buf, false);
	if (quad == null) {
		io::eprintfn("failed to map gpu transfer buffer: %s", sdl::get_error());
		libc::exit(1);
	}

	/* v1            v4
	 * +-------------+
	 * |           _/|
	 * |         _/  |
	 * |   1   _/    |
	 * |     _/      |
	 * |   _/        |
	 * | _/     2    |
	 * |/            |
	 * +-------------+
	 * v2            v3
	 */	
	quad.vertices.v1 = {.pos = {.x = x, .y = y}, .col.u = color};
	quad.vertices.v2 = {.pos = {.x = x, .y = (float)y+h}, .col.u = color};
	quad.vertices.v3 = {.pos = {.x = (float)x+w, .y = (float)y+h}, .col.u = color};
	quad.vertices.v4 = {.pos = {.x = (float)x+w, .y = y}, .col.u = color};
	
	quad.vertices.v1.norm(640.0, 480.0);
	quad.vertices.v2.norm(640.0, 480.0);
	quad.vertices.v3.norm(640.0, 480.0);
	quad.vertices.v4.norm(640.0, 480.0);

	// triangle 1
	quad.indices.i1 = 0; // v1
	quad.indices.i2 = 1; // v2
	quad.indices.i3 = 3; // v4
	// triangle 2
	quad.indices.i4 = 1; // v2
	quad.indices.i5 = 2; // v3
	quad.indices.i6 = 3; // v4

	sdl::unmap_gpu_transfer_buffer(self.gpu, buf);

	GPUCommandBuffer* cmd = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmd == null) {
		io::eprintfn("failed to upload quad at acquiring command buffer: %s", sdl::get_error());
		libc::exit(1);
	}
	GPUCopyPass* cpy = sdl::begin_gpu_copy_pass(cmd);

	// upload vertices
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = buf, .offset = Quad.vertices.offsetof},
		&&(GPUBufferRegion){.buffer = self.quad_buffer.vert_buf, .offset = 0, .size = Quad.vertices.sizeof},
		false
	);
	// upload indices
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = buf, .offset = Quad.indices.offsetof},
		&&(GPUBufferRegion){.buffer = self.quad_buffer.idx_buf, .offset = 0, .size = Quad.indices.sizeof},
		false
	);

	sdl::end_gpu_copy_pass(cpy);
	if (!sdl::submit_gpu_command_buffer(cmd)) {
		unreachable("failed to upload quads at submit command buffer: %s", sdl::get_error());
	}
	sdl::release_gpu_transfer_buffer(self.gpu, buf);
	sdl::wait_for_gpu_idle(self.gpu);

/*
	// now finally draw the quad
	// if we are not in a render pass then we can't render shit
	if (self.render_cmd == null) {
		unreachable("start rendering first before trying to render a quad");
	}

	// FIXME: this could be done at the start of rendering
	GPUTexture* t;
	if (!sdl::wait_and_acquire_gpu_swapchain_texture(self.render_cmd, self.win, &t, null, null)) {
		unreachable("failed to acquire swapchain texture: %s", sdl::get_error());
	} 

	// TODO: begin render pass
	
	Pipeline* p = self.pipelines.get_from_name(shader_name);
	if (p == null) {
		unreachable("no pipeline named: %s", shader_name);
	}

	// bind the data
	sdl::bind_gpu_graphics_pipeline(self.render_pass, pipeline);
	sdl::bind_gpu_vertex_buffer(self.render_pass, 0, 
		&&(GPUBufferBinding){.buffer = self.quad_buffer.vert_buf, .offset = 0}, 1
	);
	sdl::bind_gpu_index_buffer(self.render_pass, 0, 
		&&(GPUBufferBinding){.buffer = self.quad_buffer.idx_buf, .offset = 0}, 1
	);

	sdl::draw_gpu_indexed_primitives(self.render_pass, 6, 1, 0, 0, 0);
*/
}

// TODO: fn Renderer.draw_quad, it has to use a vertex buffer and an index buffer
// TODO: fn Renderer.draw_sprite, same as draw_quad but also bind the texture
// TODO: fn Renderer.begin_render
// TODO: fn Renderer.end_render