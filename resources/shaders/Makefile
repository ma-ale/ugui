SOURCE_DIR := ./source
COMPILED_DIR := ./compiled

SOURCE_FILES := $(wildcard $(SOURCE_DIR)/*.glsl)

COMPILED_FILES := $(patsubst $(SOURCE_DIR)/%.glsl,$(COMPILED_DIR)/%.spv,$(SOURCE_FILES))

all: $(COMPILED_FILES)
	@echo "Compiling shaders from $(SOURCE_DIR) -> $(COMPILED_DIR)"

$(COMPILED_DIR)/%.spv: $(SOURCE_DIR)/%.glsl
	@mkdir -p $(COMPILED_DIR)
	@stage=$$(basename $< .glsl | cut -d. -f2); \
	if [ "$$stage" = "frag" ] || [ "$$stage" = "vert" ]; then \
		echo "$$stage $(notdir $<) > $(notdir $@)"; \
		glslc -O0 -g -fshader-stage=$$stage $< -o $@; \
	else \
		echo "Skipping $<: unsupported stage $$stage"; \
	fi

$(COMPILED_DIR):
	mkdir -p $(COMPILED_DIR)

.PHONY: clean
clean:
	rm -rf $(COMPILED_DIR)

.PHONY: tree
tree:
	tree $(COMPILED_DIR)

.PHONY: compile_all
compile_all: clean all tree
