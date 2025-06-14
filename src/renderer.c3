module idlist{Type};

// extends the List type to search elements that have a type.id property
// TODO: check that type has an id

import std::collections::list;

alias IdList = List{Type};

macro Type* IdList.get_from_name(&self, String name)
{
	return self.get_from_id(name.hash());
}

macro Type* IdList.get_from_id(&self, id)
{
	foreach(&s: self) {
		if (s.id == id) {
			return s;
		}
	}
	return null;
}

module sdlrenderer::ren;

// 2D renderer for ugui, based on SDL3 using the new GPU API

import std::io;
import std::core::mem;
import sdl3::sdl;
import idlist;
import ugui;

struct Shader {
	sdl::GPUShader* frag;
	sdl::GPUShader* vert;
	ugui::Id id;
}

struct Pipeline {
	sdl::GPUGraphicsPipeline* pipeline;
	ugui::Id id;
}

struct Texture {
	sdl::GPUTexture* texture;
	sdl::GPUSampler* sampler;
	ushort width, height;
	ugui::Id id;
}

// The GPU buffers that contain quad info, the size is determined by MAX_QUAD_BATCH
const int MAX_QUAD_BATCH = 2048;
struct QuadBuffer {
	sdl::GPUBuffer* vert_buf; // GPU vertex buffer
	sdl::GPUBuffer* idx_buf;  // GPU index buffer
	sdl::GPUBuffer* ind_buf;  // GPU indirect render commands buffer

	// driver-side transfer buffers
	sdl::GPUTransferBuffer* vertex_ts;
	sdl::GPUTransferBuffer* index_ts;
	sdl::GPUTransferBuffer* indirect_ts;
	// driver-side transfer buffer mappings
	Vertex[] vertex_ts_mapped;
	short[] index_ts_mapped;
	sdl::GPUIndexedIndirectDrawCommand* indirect_ts_mapped;

	int count;
	int off; // the offset to draw from

	bool initialized;
}

alias ShaderList   = IdList{Shader};
alias PipelineList = IdList{Pipeline};
alias TextureList  = IdList{Texture};

struct Renderer {
	sdl::Window* win;
	sdl::GPUDevice* gpu;
	sdl::GPURenderPass* render_pass;
	sdl::GPUTexture* swapchain_texture;
	sdl::GPUCommandBuffer* render_cmdbuf;

	QuadBuffer quad_buffer;
	ShaderList shaders;
	PipelineList pipelines;
	TextureList textures;

	Id sprite_atlas_id;
	Id font_atlas_id;

	uint scissor_x, scissor_y, scissor_w, scissor_h; 
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

struct ViewsizeUniform @align(16) {
	int w, h;
}

const int DEBUG = 1;
const bool CYCLE = true;

fn void Renderer.init(&self, ZString title, uint width, uint height, bool vsync)
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
	// in debug mode set the video driver to X11 because renderdoc
	// doesn't support debugging in wayland yet. 
	sdl::set_hint(sdl::HINT_VIDEO_DRIVER, "x11");
	sdl::set_hint(sdl::HINT_RENDER_GPU_DEBUG, "1");
$endif

	// init subsystems
	if (!sdl::init(INIT_VIDEO)) {
		unreachable("sdl error: %s", sdl::get_error());
	}

	// create the window
	self.win = sdl::create_window(title, width, height, WINDOW_RESIZABLE|WINDOW_VULKAN);
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

	// set swapchain parameters, like vsync
	GPUPresentMode present_mode = vsync ? GPU_PRESENTMODE_VSYNC : GPU_PRESENTMODE_IMMEDIATE;
	sdl::set_gpu_swapchain_parameters(self.gpu, self.win, GPU_SWAPCHAINCOMPOSITION_SDR, present_mode);

	//
	// initialize the quad buffer
	// ==========================
	QuadBuffer* qb = &self.quad_buffer;

	// create the vertex and index buffer on the gpu
	qb.vert_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_VERTEX, .size = Quad.vertices.sizeof * MAX_QUAD_BATCH}
	);
	if (qb.vert_buf == null) {
		unreachable("failed to initialize quad buffer (vertex): %s", sdl::get_error());
	}

	qb.idx_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_INDEX, .size = Quad.indices.sizeof * MAX_QUAD_BATCH}
	);
	if (qb.idx_buf == null) {
		unreachable("failed to initialize quad buffer (index): %s", sdl::get_error());
	}

	qb.ind_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_INDIRECT, .size = GPUIndexedIndirectDrawCommand.sizeof * MAX_QUAD_BATCH}
	);
	if (qb.ind_buf == null) {
		unreachable("failed to initialize quad buffer (indirect commands): %s", sdl::get_error());
	}


	// allocate the transfer buffers for the vertices and indices
	qb.vertex_ts = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = Quad.vertices.sizeof * MAX_QUAD_BATCH}
	);
	if (qb.vertex_ts == null) {
		unreachable("failed to create gpu vertex transfer buffer: %s", sdl::get_error());
	}

	qb.index_ts = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = Quad.indices.sizeof * MAX_QUAD_BATCH}
	);
	if (qb.index_ts == null) {
		unreachable("failed to create gpu index transfer buffer: %s", sdl::get_error());
	}

	qb.indirect_ts = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){
			.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD,
			.size = GPUIndexedIndirectDrawCommand.sizeof * MAX_QUAD_BATCH
		}
	);
	if (qb.indirect_ts == null) {
		unreachable("failed to create gpu indirect command transfer buffer: %s", sdl::get_error());
	}


	// map the transfer buffers
	qb.vertex_ts_mapped = ((Vertex*)sdl::map_gpu_transfer_buffer(self.gpu, qb.vertex_ts, false))[:MAX_QUAD_BATCH];
	qb.index_ts_mapped = ((short*)sdl::map_gpu_transfer_buffer(self.gpu, qb.index_ts, false))[:MAX_QUAD_BATCH];
	qb.indirect_ts_mapped = ((GPUIndexedIndirectDrawCommand*)sdl::map_gpu_transfer_buffer(self.gpu, qb.indirect_ts, false))[:MAX_QUAD_BATCH];
	if (qb.vertex_ts_mapped.ptr == null || qb.index_ts_mapped.ptr == null || qb.indirect_ts_mapped == null) {
		unreachable("failed to map vertex or index buffers: %s", sdl::get_error());
	}


	qb.initialized = true;
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

	// FIXME: release the quad buffer

	sdl::release_window_from_gpu_device(self.gpu, self.win);
	sdl::destroy_gpu_device(self.gpu);
	sdl::destroy_window(self.win);
	sdl::quit();
}

fn void Renderer.resize_window(&self, uint width, uint height)
{
	sdl::set_window_size(self.win, width, height);
}

fn void Renderer.get_window_size(&self, int* width, int* height)
{
	sdl::get_window_size_in_pixels(self.win, width, height);
}


// Both the vertex shader and fragment shader have an implicit uniform buffer at binding 0 that
// contains the viewport size. It is populated automatically at every begin_render() call
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
			.num_uniform_buffers = 1+uniforms,
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
			.num_uniform_buffers = 1,
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

macro void Renderer.new_texture(&self, name_or_id, TextureType type, char[] pixels, uint width, uint height)
{
	$switch $typeof(name_or_id):
	$case usz: return self.new_texture_by_id(id, type, pixels, width, height);
	$case String: return self.new_texture_by_id(name_or_id.hash(), type, pixels, width, height);
	$default: unreachable("texture must have a name (String) or an id (usz)");
	$endswitch
}

macro void Renderer.update_texture(&self, name_or_id, char[] pixels, uint width, uint height, uint x = 0, uint y = 0)
{
	$switch $typeof(name_or_id):
	$case usz: return self.update_texture_by_id(name_or_id, pixels, width, height, x, y);
	$case String: return self.update_texture_by_id(name_or_id.hash(), pixels, width, height, x, y);
	$default: unreachable("texture must have a name (String) or an id (usz)");
	$endswitch
}


// create a new gpu texture from a pixel buffer, the format has to be specified
// the new texture s given an id and pushed into a texture list
fn void Renderer.new_texture_by_id(&self, Id id, TextureType type, char[] pixels, uint width, uint height)
{	
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
		unreachable("failed to create texture (id: %s, type: %s): %s", id, type.nameof, sdl::get_error());
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
		unreachable("failed to create sampler (texture id: %s, type: %s): %s", id, type.nameof, sdl::get_error());
	}

	Texture t = {
		.id = id,
		.texture = texture,
		.sampler = sampler,
	};
	self.textures.push(t);

	// upload the texture data
	self.update_texture_by_id(id, pixels, width, height, 0, 0);
}

fn void Renderer.update_texture_by_id(&self, Id id, char[] pixels, uint width, uint height, uint x, uint y)
{
	Texture* t = self.textures.get_from_id(id);
	if (t == null || t.texture == null) {
		unreachable("failed updating texture: no texture with id %s", id);
	}
	GPUTexture* texture = t.texture;

	// FIXME: do a better job at validating the copy
	if (x > t.width || y > t.height) {
		unreachable("failed updating texture: attempting to copy outside of the texture region");
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

	char* gpu_mem = (char*)sdl::map_gpu_transfer_buffer(self.gpu, buf, CYCLE);
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


fn bool Renderer.push_sprite(&self, short x, short y, short w, short h, short u, short v, uint color = 0xffffffff)
{
	Quad quad;
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
	quad.vertices.v1 = {.pos = {.x = x,   .y = y},   .uv = {.u = u, .v = v},     .col.u = color};
	quad.vertices.v2 = {.pos = {.x = x,   .y = y+h}, .uv = {.u = u, .v = v+h},   .col.u = color};
	quad.vertices.v3 = {.pos = {.x = x+w, .y = y+h}, .uv = {.u = u+w, .v = v+h}, .col.u = color};
	quad.vertices.v4 = {.pos = {.x = x+w, .y = y},   .uv = {.u = u+w, .v = v},   .col.u = color};
	// triangle 1 indices
	quad.indices.i1 = 0; // v1
	quad.indices.i2 = 1; // v2
	quad.indices.i3 = 3; // v4
	// triangle 2 indices
	quad.indices.i4 = 1; // v2
	quad.indices.i5 = 2; // v3
	quad.indices.i6 = 3; // v4

	return self.upload_quad(&quad);
}

// Push a quad into the quad buffer, return true on success and false on failure
fn bool Renderer.push_quad(&self, short x, short y, short w, short h, uint color, ushort radius = 0)
{
	Quad quad;
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
	// the wanted radius is pushed into the uv coordinates, the vertex shader then extracts the absolute value
	// and passes it to the fragment shader, then it uses the sign to give the fragment shader local coordinates
	// into the quad.
	quad.vertices.v1 = {.pos = {.x = x,   .y = y},   .uv = {.u = -radius, .v = +radius}, .col.u = color};
	quad.vertices.v2 = {.pos = {.x = x,   .y = y+h}, .uv = {.u = -radius, .v = -radius}, .col.u = color};
	quad.vertices.v3 = {.pos = {.x = x+w, .y = y+h}, .uv = {.u = +radius, .v = -radius}, .col.u = color};
	quad.vertices.v4 = {.pos = {.x = x+w, .y = y},   .uv = {.u = +radius, .v = +radius}, .col.u = color};
	// triangle 1 indices
	quad.indices.i1 = 0; // v1
	quad.indices.i2 = 1; // v2
	quad.indices.i3 = 3; // v4
	// triangle 2 indices
	quad.indices.i4 = 1; // v2
	quad.indices.i5 = 2; // v3
	quad.indices.i6 = 3; // v4

	return self.upload_quad(&quad);
}

// this does not upload a quad, but it simply copies the quad data to the correct transfer buffers.
// Data transfer to the GPU only happens in draw_quads() to save time
fn bool Renderer.upload_quad(&self, Quad* source_quad)
{
	if (self.quad_buffer.count >= MAX_QUAD_BATCH || source_quad == null) {
		return false;
	}
	QuadBuffer* qb = &self.quad_buffer;

	// upload the quad data to the gpu
	if (qb.initialized == false) {
		unreachable("quad buffer not initialized");
	}

	qb.vertex_ts_mapped[qb.count*4 + 0] = source_quad.vertices.v1;
	qb.vertex_ts_mapped[qb.count*4 + 1] = source_quad.vertices.v2;
	qb.vertex_ts_mapped[qb.count*4 + 2] = source_quad.vertices.v3;
	qb.vertex_ts_mapped[qb.count*4 + 3] = source_quad.vertices.v4;

	qb.index_ts_mapped[qb.count*6 + 0] = source_quad.indices.i1;
	qb.index_ts_mapped[qb.count*6 + 1] = source_quad.indices.i2;
	qb.index_ts_mapped[qb.count*6 + 2] = source_quad.indices.i3;
	qb.index_ts_mapped[qb.count*6 + 3] = source_quad.indices.i4;
	qb.index_ts_mapped[qb.count*6 + 4] = source_quad.indices.i5;
	qb.index_ts_mapped[qb.count*6 + 5] = source_quad.indices.i6;

	qb.indirect_ts_mapped[qb.count] = {6, 1, qb.count*6, qb.count*4, 0};

	qb.count++;

	return true;
}

// draw all quads in the quad buffer, since uniforms are per-drawcall it makes no sense
// to draw them one a the time
fn void Renderer.draw_quads(&self)
{
	QuadBuffer* qb = &self.quad_buffer;

	if (qb.off == qb.count) return;

	// upload quads
	GPUCommandBuffer* cmd = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmd == null) {
		unreachable("failed to upload quad at acquiring command buffer: %s", sdl::get_error());
	}
	GPUCopyPass* cpy = sdl::begin_gpu_copy_pass(cmd);

	// upload vertices
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = qb.vertex_ts, .offset = qb.off * Quad.vertices.sizeof},
		&&(GPUBufferRegion){.buffer = qb.vert_buf, .offset = qb.off * Quad.vertices.sizeof, .size = Quad.vertices.sizeof * (long)(qb.count - qb.off)},
		false
	);
	// upload indices
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = qb.index_ts, .offset = qb.off * Quad.indices.sizeof},
		&&(GPUBufferRegion){.buffer = qb.idx_buf, .offset = qb.off * Quad.indices.sizeof, .size = Quad.indices.sizeof * (long)(qb.count - qb.off)},
		false
	);
	// upload commands
	sdl::upload_to_gpu_buffer(cpy, 
		&&(GPUTransferBufferLocation){.transfer_buffer = qb.indirect_ts, .offset = qb.off * GPUIndexedIndirectDrawCommand.sizeof},
		&&(GPUBufferRegion){.buffer = qb.ind_buf, .offset = qb.off * GPUIndexedIndirectDrawCommand.sizeof, .size = GPUIndexedIndirectDrawCommand.sizeof * (long)(qb.count - qb.off)},
		false
	);

	sdl::end_gpu_copy_pass(cpy);
	if (!sdl::submit_gpu_command_buffer(cmd)) {
		unreachable("failed to upload quads at submit command buffer: %s", sdl::get_error());
	}

		//sdl::bind_gpu_vertex_buffers(self.render_pass, 0, (GPUBufferBinding[]){{.buffer = qb.vert_buf, .offset = qb.off*Quad.vertices.sizeof}}, 1);
		sdl::bind_gpu_vertex_buffers(self.render_pass, 0, (GPUBufferBinding[]){{.buffer = qb.vert_buf, .offset = 0}}, 1);
		//sdl::bind_gpu_index_buffer(self.render_pass, &&(GPUBufferBinding){.buffer = qb.idx_buf, .offset = qb.off*Quad.indices.sizeof}, GPU_INDEXELEMENTSIZE_16BIT);
		sdl::bind_gpu_index_buffer(self.render_pass, &&(GPUBufferBinding){.buffer = qb.idx_buf, .offset = 0}, GPU_INDEXELEMENTSIZE_16BIT);

	//// we need instancing to not do this
	//for (int i = 0; i < qb.count - qb.off; i++) {
	//	sdl::draw_gpu_indexed_primitives(self.render_pass, 6, 1, i*6, i*4, 0);
	//}

	sdl::draw_gpu_indexed_primitives_indirect(self.render_pass, qb.ind_buf, qb.off * GPUIndexedIndirectDrawCommand.sizeof, qb.count - qb.off);

	qb.off = qb.count;
}

fn void Renderer.reset_quads(&self)
{
	self.quad_buffer.count = 0;
	self.quad_buffer.off = 0;
}


fn void Renderer.begin_render(&self, bool clear_screen)
{
	self.render_cmdbuf = sdl::acquire_gpu_command_buffer(self.gpu);
	sdl::wait_and_acquire_gpu_swapchain_texture(self.render_cmdbuf, self.win, &self.swapchain_texture, null, null);

	// push the window size as a uniform
	// TODO: maybe make this configurable and/or add more things
	ViewsizeUniform v;
	self.get_window_size(&v.w, &v.h);
	sdl::push_gpu_vertex_uniform_data(self.render_cmdbuf, 0, &v, ViewsizeUniform.sizeof);
	sdl::push_gpu_fragment_uniform_data(self.render_cmdbuf, 0, &v, ViewsizeUniform.sizeof);

	if (clear_screen) {
		GPURenderPass* pass = sdl::begin_gpu_render_pass(self.render_cmdbuf, 
			&&(GPUColorTargetInfo){
				.texture = self.swapchain_texture,
				.mip_level = 0,
				.layer_or_depth_plane = 0,
				.clear_color = {.r = 1.0, .g = 0.0, .b = 1.0, .a = 1.0},
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

		sdl::end_gpu_render_pass(pass);
	}
}

fn void Renderer.end_render(&self)
{
	sdl::submit_gpu_command_buffer(self.render_cmdbuf);
	self.reset_quads();
}

fn void Renderer.start_render_pass(&self, String pipeline_name)
{
	self.render_pass = sdl::begin_gpu_render_pass(self.render_cmdbuf, 
		&&(GPUColorTargetInfo){
			.texture = self.swapchain_texture,
			.mip_level = 0,
			.layer_or_depth_plane = 0,
			.clear_color = {.r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0},
			.load_op = GPU_LOADOP_DONT_CARE,
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

	if (self.render_pass == null) {
		unreachable("render pass creation went wrong: %s", sdl::get_error());
	}

	sdl::GPUGraphicsPipeline* p;
	p = self.pipelines.get_from_name(pipeline_name).pipeline;
	if (p == null) {
		unreachable("no pipeline");
	}

	sdl::bind_gpu_graphics_pipeline(self.render_pass, p);
}

fn void Renderer.end_render_pass(&self)
{
	sdl::end_gpu_render_pass(self.render_pass);	
}

fn void Renderer.bind_texture(&self, String texture_name)
{
	ren::Texture* tx = self.textures.get_from_name(texture_name);
	sdl::bind_gpu_fragment_samplers(self.render_pass, 0, 
		(GPUTextureSamplerBinding[]){{.texture = tx.texture, .sampler = tx.sampler}}, 1
	);
}

fn void Renderer.set_scissor(&self, uint x, uint y, uint w, uint h)
{
	sdl::set_gpu_scissor(self.render_pass, &&(sdl::Rect){x,y,w,h});
}

fn void Renderer.reset_scissor(&self)
{
	int w, h;
	sdl::get_window_size(self.win, &w, &h);
	self.set_scissor(0, 0, w, h);
}

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
 /// === END NOTES ===


fn void Renderer.render_ugui(&self, CmdQueue* queue)
{
	Cmd* last_command;
	for (Cmd* cmd; (cmd = queue.dequeue() ?? null) != null;) {
		if (last_command == null || last_command.type != cmd.type) {
			self.end_command(last_command);
			self.begin_command(cmd);
		}

		switch (cmd.type) {
		case CMD_RECT:
			CmdRect r = cmd.rect;
			self.push_quad(r.rect.x, r.rect.y, r.rect.w, r.rect.h, r.color.to_uint(), r.radius);
		case CMD_SPRITE:
			// TODO: support hue in sprite
			CmdSprite s = cmd.sprite;
			self.push_sprite(s.rect.x, s.rect.y, s.texture_rect.w, s.texture_rect.h, s.texture_rect.x, s.texture_rect.y);
		case CMD_UPDATE_ATLAS:
			// TODO: verify the correct type
			CmdUpdateAtlas u = cmd.update_atlas;
			char[] pixels = u.raw_buffer[..u.width*u.height*u.bpp];
			self.update_texture(u.id, pixels, u.width, u.height);
		case CMD_SCISSOR:
			ugui::Rect s = cmd.scissor.rect;
			if (s.x == 0 && s.y == 0 && s.w == 0 && s.h == 0) {
				self.get_window_size((int*)&s.w, (int*)&s.h);
			}
			self.scissor_x = s.x;
			self.scissor_y = s.y;
			self.scissor_w = s.w;
			self.scissor_h = s.h;
		default: unreachable("unknown command: %s", cmd.type);
		}

		last_command = cmd;
	}
	self.end_command(last_command);
}

fn void Renderer.begin_command(&self, Cmd* cmd)
{
	if (cmd == null) return;

	switch (cmd.type) {
	case CMD_RECT:
		self.start_render_pass("UGUI_PIPELINE_RECT");
		self.set_scissor(self.scissor_x, self.scissor_y, self.scissor_w, self.scissor_h);
	case CMD_SPRITE:
		// TODO: support multiple sprite and font atlases
		CmdSprite s = cmd.sprite;
		String pipeline;
		String texture;
		if (s.texture_id == self.sprite_atlas_id) {
			switch (s.type) {
			case SPRITE_NORMAL: pipeline = "UGUI_PIPELINE_SPRITE";
			case SPRITE_SDF: pipeline = "UGUI_PIPELINE_SPRITE_SDF";
			case SPRITE_MSDF: pipeline = "UGUI_PIPELINE_SPRITE_MSDF";
			case SPRITE_ANIMATED: unreachable("animated sprtes are unsupported for now");
			default: unreachable("unknown sprite type %s", s.type);
			}
			texture = "icons";
		} else if (s.texture_id == self.font_atlas_id) {
			pipeline = "UGUI_PIPELINE_FONT";
			texture = "font1";
		}
		self.start_render_pass(pipeline);
		self.bind_texture(texture);
		self.set_scissor(self.scissor_x, self.scissor_y, self.scissor_w, self.scissor_h);
	case CMD_UPDATE_ATLAS: break;
	case CMD_SCISSOR: break;
	default: unreachable("unknown command: %s", cmd.type);
	}
}

fn void Renderer.end_command(&self, Cmd* cmd)
{
	if (cmd == null) return;

	switch (cmd.type) {
		case CMD_RECT: nextcase;
		case CMD_SPRITE:
			self.draw_quads();
			self.end_render_pass();
		case CMD_UPDATE_ATLAS: break;
		case CMD_SCISSOR: break;
		default: unreachable("unknown command: %s", cmd.type);
	}
}
