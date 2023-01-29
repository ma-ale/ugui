#ifndef _FARBFELD_EZ_H
#define _FARBFELD_EZ_H


#include <stdint.h>


struct __attribute__((packed)) ff_px { uint16_t r, g, b, a; };

struct __attribute__((packed)) ff {
	int8_t magic[8];
	uint32_t width, height;
	struct ff_px pixels[];
};


struct ff * ff_new(uint32_t width, uint32_t height);
int ff_verify (const struct ff *image);
int ff_free(struct ff *image);
uint64_t ff_bytes(const struct ff *image);
struct ff * ff_resize(struct ff *image, uint32_t width, uint32_t height);
int ff_overlay_8r(struct ff **image, const uint8_t *bitmap, uint32_t x, uint32_t y, uint32_t w, uint32_t h);


#endif
