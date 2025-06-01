#!/bin/sh

source_directory="./resources/shaders/source"
compiled_directory="./resources/shaders/compiled"
#vulkan_version="1.0"

mkdir -p "$compiled_directory"
rm -f "$compiled_directory"/*

echo "Compiling from $source_directory -> $compiled_directory"

for file in "$source_directory"/*; do
    [ -f "$file" ] || continue  # Skip non-files
    filename=$(basename "$file")
    
    # Extract filename parts using POSIX parameter expansion
    shader_language="${filename##*.}"
    stage_part="${filename%.*}"  # Remove extension
    base_name="${stage_part%.*}" # Remove stage
    stage="${stage_part#"$base_name"}"
    stage="${stage#.}"  # Remove leading dot
    
    # Skip if not in base.stage.glsl format
    [ "$shader_language" = "glsl" ] && [ -n "$base_name" ] && [ -n "$stage" ] || continue

    # Handle HLSL rejection
    if [ "$shader_language" != "glsl" ]; then 
        echo "Error: Only GLSL shaders are supported" >&2
        exit 1
    fi

    # Compile based on shader stage
    case "$stage" in
        frag|vert)
            echo "$stage $filename > $base_name.$stage.spv"
            glslc -O0 -g -fshader-stage="$stage" "$file" -o "$compiled_directory/$base_name.$stage.spv"
            ;;
    esac
done

tree "$compiled_directory"