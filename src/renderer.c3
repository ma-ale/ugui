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

// The GPU buffers that contain quad info, the size is determined by MAX_QUAD_BATCH
const int MAX_QUAD_BATCH = 128;
struct QuadBuffer {
	sdl::GPUBuffer* vert_buf;
	sdl::GPUBuffer* idx_buf;
	bool initialized;
	int count;
	int off; // the offset to draw from
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
		short x, y;
	}
	struct uv {
		short u, v;
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
	// in debug mode set the video driver to X11 because renderdoc/
	// doesn't support debugging in wayland yet. 
	sdl::set_hint(sdl::HINT_VIDEO_DRIVER, "x11");
$endif


	sdl::set_hint(sdl::HINT_RENDER_GPU_DEBUG, "1");

	// init subsystems
	if (!sdl::init(INIT_VIDEO)) {
		unreachable("sdl error: %s", sdl::get_error());
	}

	// create the window
	self.win = sdl::create_window(title, 640, 480, WINDOW_RESIZABLE|WINDOW_VULKAN);
	if (self.win == null) {
		unreachable("sdl error: %s", sdl::get_error());
	}

	// get the gpu device handle
	self.gpu = sdl::create_gpu_device(GPU_SHADERFORMAT_SPIRV, true, "vulkan");
	if (self.gpu == null) {
		unreachable("failed to create gpu device: %s", sdl::get_error());
	}

	if (!sdl::claim_window_for_gpu_device(self.gpu, self.win)) {
		unreachable("failed to claim window for use with gpu: %s", sdl::get_error());
	}

	//
	// initialize the quad buffer
	// ==========================
	self.quad_buffer.vert_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_VERTEX, .size = Quad.vertices.sizeof * MAX_QUAD_BATCH}
	);
	if (self.quad_buffer.vert_buf == null) {
		unreachable("failed to initialize quad buffer (vertex): %s", sdl::get_error());
	}

	self.quad_buffer.idx_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_INDEX, .size = Quad.indices.sizeof * MAX_QUAD_BATCH}
	);
	if (self.quad_buffer.idx_buf == null) {
		unreachable("failed to initialize quad buffer (index): %s", sdl::get_error());
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
			unreachable("failed to create gpu vertex shader: %s", sdl::get_error());
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
			unreachable("failed to create gpu fragment shader: %s", sdl::get_error());
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
	vert_code = mem::new_array(char, file::get_size(vert_path)!!+1);
	file::load_buffer(vert_path, vert_code)!!;
	defer mem::free(vert_code);

	// create fragment shader
	frag_code = mem::new_array(char, file::get_size(frag_path)!!+1);
	file::load_buffer(frag_path, frag_code)!!;
	defer mem::free(frag_code);

	self.load_spirv_shader_from_mem(name, vert_code, frag_code, textures, uniforms);
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
		unreachable("error in creating pipeline: no shader named %s", shader_name);
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
					.format = GPU_VERTEXELEMENTFORMAT_SHORT2,
					.offset = Vertex.pos.offsetof,
				},
				{ // at location one there are the uv coordinates
					.location = 1,
					.buffer_slot = 0,
					.format = GPU_VERTEXELEMENTFORMAT_SHORT2,
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
		unreachable("failed to create pipeline (shaders: %s, type: %s): %s", shader_name, type.nameof, sdl::get_error());
	}

	self.pipelines.push(p);
}

// NOTE: with TEXTUREUSAGE_SAMPLER the texture format cannot be intger _UINT so it has to be nermalized
enum TextureType : (GPUTextureFormat format) {
	FULL_COLOR = GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
	JUST_ALPHA = GPU_TEXTUREFORMAT_R8_UNORM
} 

// create a new gpu texture from a pixel buffer, the format has to be specified
// the new texture s given an id and pushed into a texture list
fn void Renderer.new_texture(&self, String name, TextureType type, char[] pixels, uint width, uint height)
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
		.num_levels = 1, // no mip maps so just one level
		// .sample_count not used since the texture is not a render target
	};

	GPUTexture* texture = sdl::create_gpu_texture(self.gpu, &tci);
	if (texture == null) {
		unreachable("failed to create texture (name: %s, type: %s): %s", name, type.nameof, sdl::get_error());
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
		unreachable("failed to create sampler (texture name: %s, type: %s): %s", name, type.nameof, sdl::get_error());
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

fn void Renderer.update_texture(&self, String name, char[] pixels, uint width, uint height, uint x = 0, uint y = 0)
{
	Texture* t = self.textures.get_from_name(name);
	if (t == null || t.texture == null) {
		unreachable("failed updating texture: no texture named %s", name);
	}
	GPUTexture* texture = t.texture;

	// FIXME: do a better job at validating the copy
	if (x > t.width || y > t.height) {
		unreachable("failed updating texture: attempting to copy outside of the texture region", name);
	}

	// upload image data
	GPUCommandBuffer* cmdbuf = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmdbuf == null) {
		unreachable("failed to upload texture data at acquiring command buffer: %s", sdl::get_error());
	}
	GPUCopyPass* copypass = sdl::begin_gpu_copy_pass(cmdbuf);
	if (copypass == null) {
		unreachable("failed to upload texture data at beginning copy pass: %s", sdl::get_error());
	}

	GPUTransferBuffer* buf = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = pixels.len}
	);
	if (buf == null) {
		unreachable("failed to upload texture data at creating the transfer buffer: %s", sdl::get_error());
	}

	char* gpu_mem = (char*)sdl::map_gpu_transfer_buffer(self.gpu, buf, false);
	if (gpu_mem == null) {
		unreachable("failed to upload texture data at mapping the transfer buffer: %s", sdl::get_error());
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
		unreachable("failed to upload texture data at command buffer submission: %s", sdl::get_error());
	}
	sdl::release_gpu_transfer_buffer(self.gpu, buf);
}


fn bool Renderer.push_sprite(&self, short x, short y, short w, short h, short u, short v) {
	if (self.quad_buffer.count >= MAX_QUAD_BATCH) {
		return false;
	}

	// upload the quad data to the gpu
	if (self.quad_buffer.initialized == false) {
		unreachable("quad buffer not initialized");
	}

	GPUTransferBuffer* buf = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = Quad.sizeof}
	);
	if (buf == null) {
		unreachable("failed to create gpu transfer buffer: %s", sdl::get_error());
	}

	Quad* quad = (Quad*)sdl::map_gpu_transfer_buffer(self.gpu, buf, false);
	if (quad == null) {
		unreachable("failed to map gpu transfer buffer: %s", sdl::get_error());
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
	quad.vertices.v1 = {.pos = {.x = x,   .y = y},   .uv = {.u = u, .v = v}};
	quad.vertices.v2 = {.pos = {.x = x,   .y = y+h}, .uv = {.u = u, .v = v+h}};
	quad.vertices.v3 = {.pos = {.x = x+w, .y = y+h}, .uv = {.u = u+w, .v = v+h}};
	quad.vertices.v4 = {.pos = {.x = x+w, .y = y},   .uv = {.u = u+w, .v = v}};
	// triangle 1 indices
	quad.indices.i1 = 0; // v1
	quad.indices.i2 = 1; // v2
	quad.indices.i3 = 3; // v4
	// triangle 2 indices
	quad.indices.i4 = 1; // v2
	quad.indices.i5 = 2; // v3
	quad.indices.i6 = 3; // v4

	sdl::unmap_gpu_transfer_buffer(self.gpu, buf);

	GPUCommandBuffer* cmd = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmd == null) {
		unreachable("failed to upload quad at acquiring command buffer: %s", sdl::get_error());
	}
	GPUCopyPass* cpy = sdl::begin_gpu_copy_pass(cmd);

	// upload vertices
	QuadBuffer* qb = &self.quad_buffer;
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = buf, .offset = Quad.vertices.offsetof},
		&&(GPUBufferRegion){.buffer = qb.vert_buf, .offset = qb.count * Quad.vertices.sizeof, .size = Quad.vertices.sizeof},
		false
	);
	// upload indices
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = buf, .offset = Quad.indices.offsetof},
		&&(GPUBufferRegion){.buffer = qb.idx_buf, .offset = qb.count * Quad.indices.sizeof, .size = Quad.indices.sizeof},
		false
	);

	sdl::end_gpu_copy_pass(cpy);
	if (!sdl::submit_gpu_command_buffer(cmd)) {
		unreachable("failed to upload quads at submit command buffer: %s", sdl::get_error());
	}
	sdl::release_gpu_transfer_buffer(self.gpu, buf);
	//sdl::wait_for_gpu_idle(self.gpu);

	qb.count++;

	return true;
}

// Push a quad into the quad buffer, return true on success and false on failure
fn bool Renderer.push_quad(&self, short x, short y, short w, short h, uint color)
{
	if (self.quad_buffer.count >= MAX_QUAD_BATCH) {
		return false;
	}

	// upload the quad data to the gpu
	if (self.quad_buffer.initialized == false) {
		unreachable("quad buffer not initialized");
	}

	GPUTransferBuffer* buf = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = Quad.sizeof}
	);
	if (buf == null) {
		unreachable("failed to create gpu transfer buffer: %s", sdl::get_error());
	}

	Quad* quad = (Quad*)sdl::map_gpu_transfer_buffer(self.gpu, buf, false);
	if (quad == null) {
		unreachable("failed to map gpu transfer buffer: %s", sdl::get_error());
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
	quad.vertices.v1 = {.pos = {.x = x,   .y = y},   .col.u = color};
	quad.vertices.v2 = {.pos = {.x = x,   .y = y+h}, .col.u = color};
	quad.vertices.v3 = {.pos = {.x = x+w, .y = y+h}, .col.u = color};
	quad.vertices.v4 = {.pos = {.x = x+w, .y = y},   .col.u = color};
	// triangle 1 indices
	quad.indices.i1 = 0; // v1
	quad.indices.i2 = 1; // v2
	quad.indices.i3 = 3; // v4
	// triangle 2 indices
	quad.indices.i4 = 1; // v2
	quad.indices.i5 = 2; // v3
	quad.indices.i6 = 3; // v4

	sdl::unmap_gpu_transfer_buffer(self.gpu, buf);

	GPUCommandBuffer* cmd = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmd == null) {
		unreachable("failed to upload quad at acquiring command buffer: %s", sdl::get_error());
	}
	GPUCopyPass* cpy = sdl::begin_gpu_copy_pass(cmd);

	// upload vertices
	QuadBuffer* qb = &self.quad_buffer;
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = buf, .offset = Quad.vertices.offsetof},
		&&(GPUBufferRegion){.buffer = qb.vert_buf, .offset = qb.count * Quad.vertices.sizeof, .size = Quad.vertices.sizeof},
		false
	);
	// upload indices
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = buf, .offset = Quad.indices.offsetof},
		&&(GPUBufferRegion){.buffer = qb.idx_buf, .offset = qb.count * Quad.indices.sizeof, .size = Quad.indices.sizeof},
		false
	);

	sdl::end_gpu_copy_pass(cpy);
	if (!sdl::submit_gpu_command_buffer(cmd)) {
		unreachable("failed to upload quads at submit command buffer: %s", sdl::get_error());
	}
	sdl::release_gpu_transfer_buffer(self.gpu, buf);
	//sdl::wait_for_gpu_idle(self.gpu);

	qb.count++;

	return true;
}

// draw all quads in the quad buffer, since uniforms are per-drawcall it makes no sense
// to draw them one a the time
fn void Renderer.draw_quads(&self, GPURenderPass* pass)
{
	QuadBuffer* qb = &self.quad_buffer;

	if (qb.off == qb.count) return;

	sdl::bind_gpu_vertex_buffers(pass, 0, (GPUBufferBinding[]){{.buffer = qb.vert_buf, .offset = qb.off*Quad.vertices.sizeof}}, 1);
	sdl::bind_gpu_index_buffer(pass, &&(GPUBufferBinding){.buffer = qb.idx_buf, .offset = qb.off*Quad.indices.sizeof}, GPU_INDEXELEMENTSIZE_16BIT);

	// we need instancing to not do this
	for (int i = 0; i < qb.count - qb.off; i++) {
		sdl::draw_gpu_indexed_primitives(pass, 6, 1, i*6, i*4, 0);
	}

	qb.off = qb.count;
}

fn void Renderer.reset_quads(&self)
{
	self.quad_buffer.count = 0;
	self.quad_buffer.off = 0;
}


// TODO: fn Renderer.draw_sprite, same as draw_quad but also bind the texture
// TODO: fn Renderer.begin_render
// TODO: fn Renderer.end_render

/// === NOTES ===
/* 1. The uniform data is per-render pass. So you can do:
 *      - push uniform
 *      - draw 1
 *      - draw 2
 *    But not:
 *      - push uniform
 *      - draw
 *      - push new uniform
 *      - draw
 *    And not even:
 *      - draw
 *      - push uniform
 *      - draw
 * 
 * 2. The GPU buffers are read per-command-buffer and not per
 *    render pass. So I cannot override an element in the buffer
 *    before submitting the command buffer. 
 */