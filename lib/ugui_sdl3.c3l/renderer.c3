// extends the List type to search elements that have a type.id property
<*
 @require $defined((Type){}.id) : `No .id member found in the type`
*>
module idlist{Type};
import std::collections::list;

alias IdList = List{Type};

<*
@param [&in] self
@param [in] name
*>
macro Type* IdList.get_from_name(&self, String name)
{
	return self.get_from_id(name.hash());
}

<* @param [&in] self *>
macro Type* IdList.get_from_id(&self, id)
{
	foreach(&s: self) {
		if (s.id == id) {
			return s;
		}
	}
	return null;
}


// 2D renderer for ugui, based on SDL3 using the new GPU API
module ugui::sdl::ren;

import std::io;
import sdl3::sdl;
import std::core::mem;
import idlist;
import ugui;


// ============================================================================================== //
// CONSTANTS                                                                                      //
// ============================================================================================== //

const bool CYCLE = true;
const int MAX_QUAD_BATCH = 2048;


// ============================================================================================== //
// STRUCTURES                                                                                     //
// ============================================================================================== //

// How each vertex is represented in the gpu
struct Vertex {
	short x, y;
}

// Attributes of each quad instance
struct QuadAttributes {
	struct pos {
		short x, y, w, h;
	}
	struct uv {
		short u, v, w, h;
	}
	uint color;
	uint type;
}

// A single quad
struct Quad {
	struct vertices {
		Vertex v1,v2,v3,v4;
	}
	struct indices {
		short i1,i2,i3,i4,i5,i6;
	}
}

// the viewport size uniform passed to the gpu
struct ViewsizeUniform @align(16) {
	int w, h;
}

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
struct QuadBuffer {
	sdl::GPUBuffer* vert_buf; // on-gpu vertex buffer
	sdl::GPUBuffer* idx_buf;  // on-gpu index buffer
	sdl::GPUBuffer* attr_buf; // on-gpu quad attribute buffer

	sdl::GPUTransferBuffer* attr_ts;

	QuadAttributes[] attr_ts_mapped;

	// how many quads are currently stored
	int count;

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

	int scissor_x, scissor_y, scissor_w, scissor_h;
}


// ============================================================================================== //
// RENDERERER METHODS                                                                             //
// ============================================================================================== //


/* Initialize the renderer structure, this does a couple of things
 *   1. Initializes the SDL video subsystem with the correct hints
 *   2. Creates a window and attaches it to the gpu device
 *   3. Allocates the quad buffer and uploads the quad mesh to the GPU
 */
fn void Renderer.init(&self, ZString title, uint width, uint height, bool vsync)
{
	// set wayland hint automagically
$if $feature(RENDER_DEBUG) == false && $feature(USE_WAYLAND) == true:
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

	// since instanced rendering is used, on the gpu there is only one mesh, a single quad.

	// create the vertex and index buffer on the gpu
	qb.vert_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_VERTEX, .size = Quad.vertices.sizeof}
	);
	if (qb.vert_buf == null) {
		unreachable("failed to initialize quad buffer (vertex): %s", sdl::get_error());
	}

	qb.idx_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_INDEX, .size = Quad.indices.sizeof}
	);
	if (qb.idx_buf == null) {
		unreachable("failed to initialize quad buffer (index): %s", sdl::get_error());
	}

	qb.attr_buf = sdl::create_gpu_buffer(self.gpu,
		&&(GPUBufferCreateInfo){.usage = GPU_BUFFERUSAGE_VERTEX, .size = QuadAttributes.sizeof * MAX_QUAD_BATCH}
	);
	if (qb.attr_buf == null) {
		unreachable("failed to initialize quad buffer (index): %s", sdl::get_error());
	}

	// upload the quad mesh
	GPUTransferBuffer *ts =  sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = Quad.sizeof}
	);
	if (ts == null) {
		unreachable("failed to create gpu transfer buffer: %s", sdl::get_error());
	}
	Quad* quad = (Quad*)sdl::map_gpu_transfer_buffer(self.gpu, ts, false);

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
	quad.vertices.v1 = {.x = 0, .y = 0};
	quad.vertices.v2 = {.x = 0, .y = 1};
	quad.vertices.v3 = {.x = 1, .y = 1};
	quad.vertices.v4 = {.x = 1, .y = 0};
	// triangle 1 indices
	quad.indices.i1 = 0; // v1
	quad.indices.i2 = 1; // v2
	quad.indices.i3 = 3; // v4
	// triangle 2 indices
	quad.indices.i4 = 1; // v2
	quad.indices.i5 = 2; // v3
	quad.indices.i6 = 3; // v4

	sdl::unmap_gpu_transfer_buffer(self.gpu, ts);

	GPUCommandBuffer* cmd = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmd == null) {
		unreachable("failed to upload quad at acquiring command buffer: %s", sdl::get_error());
	}
	GPUCopyPass* cpy = sdl::begin_gpu_copy_pass(cmd);

	// upload vertices
	sdl::upload_to_gpu_buffer(cpy,
		&&(GPUTransferBufferLocation){.transfer_buffer = ts, .offset = Quad.vertices.offsetof},
		&&(GPUBufferRegion){.buffer = qb.vert_buf, .offset = 0, .size = Quad.vertices.sizeof},
		false
	);
	// upload indices
	sdl::upload_to_gpu_buffer(cpy,
		&&(GPUTransferBufferLocation){.transfer_buffer = ts, .offset = Quad.indices.offsetof},
		&&(GPUBufferRegion){.buffer = qb.idx_buf, .offset = 0, .size = Quad.indices.sizeof},
		false
	);

	sdl::end_gpu_copy_pass(cpy);
	if (!sdl::submit_gpu_command_buffer(cmd)) {
		unreachable("failed to upload quads at submit command buffer: %s", sdl::get_error());
	}
	sdl::release_gpu_transfer_buffer(self.gpu, ts);


	// create and map the quad attributes transfer buffer
	qb.attr_ts = sdl::create_gpu_transfer_buffer(self.gpu,
		&&(GPUTransferBufferCreateInfo){.usage = GPU_TRANSFERBUFFERUSAGE_UPLOAD, .size = QuadAttributes.sizeof * MAX_QUAD_BATCH}
	);
	if (qb.attr_ts == null) {
		unreachable("failed to create gpu transfer buffer: %s", sdl::get_error());
	}
	qb.attr_ts_mapped = ((QuadAttributes*)sdl::map_gpu_transfer_buffer(self.gpu, qb.attr_ts, false))[:MAX_QUAD_BATCH];
	if (qb.attr_ts_mapped.ptr == null) {
		unreachable("failed to map vertex or index buffers: %s", sdl::get_error());
	}


	qb.initialized = true;
}


/* Frees all the renderer structures:
 *   - Frees all textures and pipelines
 *   - Releases all GPU transfer buffers
 *   - Closes the main window
 *   - Releases the GPU device
 */
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

	foreach (&t: self.textures) {
		sdl::release_gpu_texture(self.gpu, t.texture);
		sdl::release_gpu_sampler(self.gpu, t.sampler);
	}
	self.textures.free();

	QuadBuffer* qb = &self.quad_buffer;
	sdl::unmap_gpu_transfer_buffer(self.gpu, qb.attr_ts);
	sdl::release_gpu_transfer_buffer(self.gpu, qb.attr_ts);
	sdl::release_gpu_buffer(self.gpu, qb.vert_buf);
	sdl::release_gpu_buffer(self.gpu, qb.idx_buf);
	sdl::release_gpu_buffer(self.gpu, qb.attr_buf);

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


// ============================================================================================== //
// SHADER LOADING                                                                                 //
// ============================================================================================== //


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
	usz size = file::get_size(vert_path)!!;
	vert_code = mem::new_array(char, size + size%4);
	file::load_buffer(vert_path, vert_code)!!;
	defer mem::free(vert_code);

	// create fragment shader
	size = file::get_size(frag_path)!!;
	frag_code = mem::new_array(char, size + size%4);
	file::load_buffer(frag_path, frag_code)!!;
	defer mem::free(frag_code);

	self.load_spirv_shader_from_mem(name, vert_code, frag_code, textures, uniforms);
}


// ============================================================================================== //
// PIPELINE CREATION                                                                              //
// ============================================================================================== //


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
			.vertex_buffer_descriptions = (GPUVertexBufferDescription[]){
				{ // first slot, per-vertex attributes
					.slot = 0,
					.pitch = Vertex.sizeof,
					.input_rate = GPU_VERTEXINPUTRATE_VERTEX,
				},
				{ // second slot, per-instance attributes
					.slot = 1,
					.pitch = QuadAttributes.sizeof,
					.input_rate = GPU_VERTEXINPUTRATE_INSTANCE,
				}
			},
			.num_vertex_buffers = 2,
			// the description of each vertex, quad and bindings
			.vertex_attributes = (GPUVertexAttribute[]){
				{ // at location zero there is the position of the vertex
					.location = 0,
					.buffer_slot = 0, // buffer slot zero so per-vertex
					.format = GPU_VERTEXELEMENTFORMAT_SHORT2, // x,y
					.offset = 0,
				},
				{ // at location one there is the per-quad position
					.location = 1,
					.buffer_slot = 1, // buffer slot one so per-instance
					.format = GPU_VERTEXELEMENTFORMAT_SHORT4, // x,y,w,h
					.offset = QuadAttributes.pos.offsetof,
				},
				{ // at location two there are the per-quad uv coordinates
					.location = 2,
					.buffer_slot = 1,
					.format = GPU_VERTEXELEMENTFORMAT_SHORT4,
					.offset = QuadAttributes.uv.offsetof,
				},
				{ // at location three there is the quad color
					.location = 3,
					.buffer_slot = 1,
					.format = GPU_VERTEXELEMENTFORMAT_UBYTE4,
					.offset = QuadAttributes.color.offsetof,
				},
				{ // at location four there is the quad type
					.location = 4,
					.buffer_slot = 1,
					.format = GPU_VERTEXELEMENTFORMAT_UINT,
					.offset = QuadAttributes.type.offsetof,
				}
			},
			.num_vertex_attributes = 5,
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


// ============================================================================================== //
// TEXTURE LOADING                                                                                //
// ============================================================================================== //



// NOTE: with TEXTUREUSAGE_SAMPLER the texture format cannot be intger _UINT so it has to be nermalized
enum TextureType : (GPUTextureFormat format) {
	FULL_COLOR = GPU_TEXTUREFORMAT_R8G8B8A8_UNORM,
	JUST_ALPHA = GPU_TEXTUREFORMAT_R8_UNORM
}


// This macro wraps new_texture_by_id() by accepting either a name or an id directly
macro void Renderer.new_texture(&self, name_or_id, TextureType type, char[] pixels, uint width, uint height)
{
	$switch $typeof(name_or_id):
	$case uint: return self.new_texture_by_id(id, type, pixels, width, height);
	$case String: return self.new_texture_by_id(name_or_id.hash(), type, pixels, width, height);
	$default: unreachable("texture must have a name (String) or an id (uint)");
	$endswitch
}


// This macro wraps update_texture_by_id() by accepting either a name or an id directly
macro void Renderer.update_texture(&self, name_or_id, char[] pixels, uint width, uint height, uint x = 0, uint y = 0)
{
	$switch $typeof(name_or_id):
	$case uint: return self.update_texture_by_id(name_or_id, pixels, width, height, x, y);
	$case String: return self.update_texture_by_id(name_or_id.hash(), pixels, width, height, x, y);
	$default: unreachable("texture must have a name (String) or an id (uint)");
	$endswitch
}


/* Create a new gpu texture from a pixel buffer, the format has to be specified.
 * The new texture is given an id and pushed into the renderer's texture list.
 */
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


/* Updates a texture on the gpu.
 *   pixels: the pixel array that contais the texture content
 *   width, height: the size of the
 */
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


// ============================================================================================== //
// RENDER COMMANDS                                                                                //
// ============================================================================================== //

const uint TYPE_RECT   = 0;
const uint TYPE_FONT   = 1;
const uint TYPE_SPRITE = 2;
const uint TYPE_MSDF   = 3;

fn bool Renderer.push_sprite(&self, short x, short y, short w, short h, short u, short v, short sw, short sh, uint color = 0xffffffff, uint type)
{
	QuadAttributes qa = {
		.pos = {.x = x, .y = y, .w = w, .h = h},
		.uv = {.u = u, .v = v, .w = sw, .h = sh},
		.color = color,
		.type = type,
	};

	return self.map_quad(qa);
}

fn bool Renderer.push_quad(&self, short x, short y, short w, short h, uint color, ushort radius, uint type)
{
	QuadAttributes qa = {
		.pos = {.x = x, .y = y, .w = w, .h = h},
		.uv  = {.u = radius, .v = radius},
		.color = color,
		.type = type
	};

	return self.map_quad(qa);
}

// this does not upload a quad, but it simply copies the quad data to the correct transfer buffers.
// Data transfer to the GPU only happens in draw_quads() to save time
fn bool Renderer.map_quad(&self, QuadAttributes qa)
{
	if (self.quad_buffer.count >= MAX_QUAD_BATCH) {
		return false;
	}
	QuadBuffer* qb = &self.quad_buffer;

	// upload the quad data to the gpu
	if (qb.initialized == false) {
		unreachable("quad buffer not initialized");
	}

	qb.attr_ts_mapped[qb.count] = qa;

	qb.count++;

	return true;
}

fn void Renderer.upload_quads(&self)
{
	QuadBuffer* qb = &self.quad_buffer;

	GPUCommandBuffer* cmd = sdl::acquire_gpu_command_buffer(self.gpu);
	if (cmd == null) {
		unreachable("failed to upload quad at acquiring command buffer: %s", sdl::get_error());
	}
	GPUCopyPass* cpy = sdl::begin_gpu_copy_pass(cmd);

	// upload quad attributes
	sdl::upload_to_gpu_buffer(cpy,
		&&(GPUTransferBufferLocation){.transfer_buffer = qb.attr_ts, .offset = 0},
		&&(GPUBufferRegion){.buffer = qb.attr_buf, .offset = 0, .size = QuadAttributes.sizeof * qb.count},
		false
	);

	sdl::end_gpu_copy_pass(cpy);
	if (!sdl::submit_gpu_command_buffer(cmd)) {
		unreachable("failed to upload quads at submit command buffer: %s", sdl::get_error());
	}
}

// draw all quads in the quad buffer, since uniforms are per-drawcall it makes no sense
// to draw them one a the time
fn void Renderer.draw_quads(&self, uint off, uint count)
{
	QuadBuffer* qb = &self.quad_buffer;

	// too many quads to draw
	if (off >= qb.count || count > qb.count - off) {
		unreachable("too many quads, have %d, requested %d, offset %d", qb.count, count, off);
	}

	sdl::bind_gpu_vertex_buffers(self.render_pass, 0,
		(GPUBufferBinding[]){
			{.buffer = qb.vert_buf, .offset = 0},
			{.buffer = qb.attr_buf, .offset = 0},
		}, 2);
	sdl::bind_gpu_index_buffer(self.render_pass, &&(GPUBufferBinding){.buffer = qb.idx_buf, .offset = 0}, GPU_INDEXELEMENTSIZE_16BIT);

	sdl::draw_gpu_indexed_primitives(self.render_pass, 6, count, 0, 0, off);
}

fn void Renderer.reset_quads(&self)
{
	self.quad_buffer.count = 0;
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


fn void Renderer.bind_textures(&self, String... texture_names)
{
	// TODO: bind in one pass
	foreach (idx, name: texture_names) {
		ren::Texture* tx = self.textures.get_from_name(name);
		if (tx == null) {
			unreachable("texture '%s' was not registered", name);
		}
		sdl::bind_gpu_fragment_samplers(self.render_pass, (uint)idx,
			(GPUTextureSamplerBinding[]){{.texture = tx.texture, .sampler = tx.sampler}}, 1
		);
	}
}


fn void Renderer.bind_textures_id(&self, ugui::Id... texture_ids)
{
	// TODO: bind in one pass
	foreach (idx, id: texture_ids) {
		ren::Texture* tx = self.textures.get_from_id(id);
		if (tx == null) {
			unreachable("texture [%d] was not registered", id);
		}
		sdl::bind_gpu_fragment_samplers(self.render_pass, (uint)idx,
			(GPUTextureSamplerBinding[]){{.texture = tx.texture, .sampler = tx.sampler}}, 1
		);
	}
}


fn void Renderer.set_scissor(&self, int x, int y, int w, int h)
{
	// in vulkan scissor size must be positive, clamp to zero
	w = max(w, 0);
	h = max(h, 0);
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
	// upload pass
	foreach (&c : queue) {
		if (c.type == CMD_RECT) {
			CmdRect r = c.rect;
			self.push_quad(r.rect.x, r.rect.y, r.rect.w, r.rect.h, r.color.to_uint(), r.radius, TYPE_RECT);
		} else if (c.type == CMD_SPRITE) {
			CmdSprite s = c.sprite;
			uint type;
			if (s.texture_id == self.font_atlas_id) {
				type = TYPE_FONT;
			} else if (s.texture_id == self.sprite_atlas_id && s.type == SPRITE_NORMAL) {
				type = TYPE_SPRITE;
			} else if (s.texture_id == self.sprite_atlas_id && s.type == SPRITE_MSDF) {
				type = TYPE_MSDF;
			} else {
				unreachable("unrecognized command type");
			}
			self.push_sprite(s.rect.x, s.rect.y, s.rect.w, s.rect.h, s.texture_rect.x, s.texture_rect.y, s.texture_rect.w, s.texture_rect.h, s.hue.to_uint(), type);
		}
	}
	self.upload_quads();

	self.start_render_pass("UGUI_PIPELINE");
	self.bind_textures_id(self.font_atlas_id, self.sprite_atlas_id);

	bool no_draws;
	uint calls = 0;
	uint off;
	while (true) {
		Cmd? cmd = queue.pop_first();
		if (catch e = cmd) {
			if (e != NO_MORE_ELEMENT) unreachable();
			break;
		}
		switch (cmd.type) {
		case CMD_REQ_SKIP_FRAME:
			no_draws = true;
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
		default:
			if (no_draws) break;

			self.set_scissor(self.scissor_x, self.scissor_y, self.scissor_w, self.scissor_h);
			uint count = 1;
			while (queue.len() != 0 && (queue.get(0).type == CMD_RECT || queue.get(0).type == CMD_SPRITE)) {
				count++;
				(void)queue.pop_first();
			}
			self.draw_quads(off, count);
			off += count;
			calls++;
		}
	}
	self.end_render_pass();
//	ugui::println("calls: ", calls);
}

