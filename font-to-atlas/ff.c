#include <arpa/inet.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include <stdio.h>

#include "ff.h"


#define MAX(a,b) a>b?a:b


struct ff * ff_new(uint32_t width, uint32_t height)
{
	uint64_t size = (uint64_t)width*height*sizeof(struct ff);
	struct ff *image = malloc(sizeof(struct ff) + size);
	if (!image)
		return NULL;
	memcpy(image->magic, "farbfeld", 8);
	image->width  = htonl(width);
	image->height = htonl(height);

	// create a transparent image
	memset(image->pixels, 0, size);

	return image;
}


uint64_t ff_bytes(const struct ff *image)
{
	if (!image)
		return 0;
	return sizeof(struct ff)+(uint64_t)ntohl(image->width)*ntohl(image->height)*sizeof(struct ff_px);
}


struct ff * ff_resize(struct ff *image, uint32_t width, uint32_t height)
{
	struct ff *new = NULL;
	int64_t size = sizeof(struct ff)+(int64_t)width*height*sizeof(uint64_t);
	if (image) {
		int64_t old_size = ff_bytes(image);
		if (old_size == size)
			return image;

		new = realloc(image, size);
		if (!new)
			return NULL;

		uint32_t old_width = ntohl(new->width);
		uint32_t old_height = ntohl(new->height);
		if (size-old_size > 0) {
			struct ff_px *b = new->pixels;
			memset(&b[old_width*old_height], 0, size-old_size);
			for (int64_t c = (int64_t)old_height-1; c >= 0; c--) {
				memmove(&b[width*c], &b[old_width*c], sizeof(struct ff_px)*old_width);
				memset(&b[c*old_width], 0, sizeof(struct ff_px)*(c*width-c*old_width));
			}
		} else {
		}
		new->height = htonl(height);
		new->width = htonl(width);

	} else {
		new = ff_new(width, height);
	}

	return new;
}


int ff_verify (const struct ff *image)
{
	if (!image || strncmp("farbfeld", (char*)image->magic, 8))
		return 1;
	return 0;
}


int ff_free(struct ff *image)
{
	if (!ff_verify(image))
		free(image);
	return 0;
}


// overlays the bitmap containing only 1 8bpp channel to the image starting at (x,y)
// be stands for the data is already big endian
int ff_overlay_8r(struct ff **image, const uint8_t *bitmap, uint32_t x, uint32_t y, uint32_t w, uint32_t h)
{
	if (!image || !*image)
		return 1;

	uint32_t iw = ntohl((*image)->width), ih = ntohl((*image)->height);
	*image = ff_resize(*image, MAX(iw, x+w), MAX(ih, y+h));
	if (!image)
		return -1;
	iw = ntohl((*image)->width);
	ih = ntohl((*image)->height);

	for (uint32_t r = 0; r < h; r++) {
		for (uint32_t c = 0; c < w; c++) {
			uint8_t col = bitmap[r*w+c];
			struct ff_px p = {
				.r = 0xffff,
				.g = 0xffff,
				.b = 0xffff,
				.a = htons(257*col)
			};
			(*image)->pixels[(r+y)*iw + (c+x)] = p;
		}
	}

	return 0;
}
