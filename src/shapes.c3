module ugui;
import std::math;

// ---------------------------------------------------------------------------------- //
//                                  RECTANGLE                                         //
// ---------------------------------------------------------------------------------- //

// Rect and it's methods
struct Rect {
	short x, y, w, h;
}

// TODO: find another name
const Rect RECT_MAX = {0, 0, short.max, short.max};

// return true if rect a contains b
macro bool Rect.contains(Rect a, Rect b)
{
	return (a.x <= b.x && a.y <= b.y && a.x+a.w >= b.x+b.w && a.y+a.h >= b.y+b.h);
}

// returns the intersection of a and b
macro Rect Rect.intersection(Rect a, Rect b)
{
	return {
		.x = (short)max(a.x, b.x),
		.y = (short)max(a.y, b.y),
		.w = (short)min(a.x+a.w, b.x+b.w) - (short)max(a.x, b.x),
		.h = (short)min(a.y+a.h, b.y+b.h) - (short)max(a.y, b.y),
	};
}

// returns true if the intersection not null
macro bool Rect.collides(Rect a, Rect b)
{
	return !(a.x > b.x+b.w || a.x+a.w < b.x || a.y > b.y+b.h || a.y+a.h < b.y);
}

// return a rect that contains both rects, a bounding box of both
macro Rect containing_rect(Rect a, Rect b)
{
	short min_x = (short)min(a.x, b.x);
	short min_y = (short)min(a.y, b.y);
	short max_x = (short)max(a.x + a.w, b.x + b.w);
	short max_y = (short)max(a.y + a.h, b.y + b.h);
	return {
		.x = min_x,
		.y = min_y,
		.w = (short)(max_x - min_x),
		.h = (short)(max_y - min_y)
	};
}

// check for empty rect
macro bool Rect.is_null(Rect r) => r.x == 0 && r.y == 0 && r.x == 0 && r.w == 0;

// returns the element-wise addition of r1 and r2
macro Rect Rect.add(Rect r1, Rect r2) @operator_s(+)
{
	return {
		.x = r1.x + r2.x,
		.y = r1.y + r2.y,
		.w = r1.w + r2.w,
		.h = r1.h + r2.h,
	};
}

// returns the element-wise subtraction of r1 and r2
macro Rect Rect.sub(Rect r1, Rect r2) @operator_s(-)
{
	return {
		.x = r1.x - r2.x,
		.y = r1.y - r2.y,
		.w = r1.w - r2.w,
		.h = r1.h - r2.h,
	};
}

// returns the element-wise multiplication of r1 and r2
macro Rect Rect.mul(Rect r1, Rect r2) @operator_s(*)
{
	return {
		.x = r1.x * r2.x,
		.y = r1.y * r2.y,
		.w = r1.w * r2.w,
		.h = r1.h * r2.h,
	};
}

macro Point Rect.position(Rect r)
{
	return {
		.x = r.x,
		.y = r.y,
	};
}

macro Point Rect.size(Rect r)
{
	return {
		.x = r.w,
		.y = r.h,
	};
}

macro Rect Rect.max(Rect a, Rect b)
{
	return {
		.x = max(a.x, b.x),
		.y = max(a.y, b.y),
		.w = max(a.w, b.w),
		.h = max(a.h, b.h),
	};
}

macro Rect Rect.min(Rect a, Rect b)
{
	return {
		.x = min(a.x, b.x),
		.y = min(a.y, b.y),
		.w = min(a.w, b.w),
		.h = min(a.h, b.h),
	};
}

// Offset a rect by a point
macro Rect Rect.off(Rect r, Point p) @operator_s(+)
{
	return {
		.x = r.x + p.x,
		.y = r.y + p.y,
		.w = r.w,
		.h = r.h,
	};
}

// Resize a rect width and height
macro Rect Rect.grow(Rect r, Point p)
{
	return {
		.x = r.x,
		.y = r.y,
		.w = r.w + p.x,
		.h = r.h + p.y,
	};
}

// Return the bottom-right corner of a rectangle
macro Point Rect.bottom_right(Rect r)
{
	return {
		.x = r.x + r.w,
		.y = r.y + r.h,
	};
}

macro Rect Rect.center_to(Rect a, Rect b)
{
	return {
		.x = b.x + (b.w - a.w)/2,
		.y = b.y + (b.h - a.h)/2,
		.w = a.w,
		.h = a.h,
	};
}

macro Rect Rect.pad(Rect a, Rect b)
{
	return {
		.x = a.x + b.x,
		.y = a.y + b.y,
		.w = a.w - b.x - b.w,
		.h = a.h - b.y - b.h,
	};
}

macro Rect Rect.expand(Rect a, Rect b)
{
	return {
		.x = a.x - b.x,
		.y = a.y - b.y,
		.w = a.w + b.x + b.w,
		.h = a.h + b.y + b.h,
	};
}

// ---------------------------------------------------------------------------------- //
//                                    POINT                                           //
// ---------------------------------------------------------------------------------- //

struct Point {
	short x, y;
}

// returns true if a point is inside the rectangle
macro bool Point.in_rect(Point p, Rect r)
{
	return (p.x >= r.x && p.x <= r.x + r.w) && (p.y >= r.y && p.y <= r.y + r.h);
}

macro bool Point.outside(Point p, Rect r) => !p.in_rect(r);

macro Point Point.add(Point a, Point b) @operator_s(+) => {.x = a.x+b.x, .y = a.y+b.y};
macro Point Point.sub(Point a, Point b) @operator_s(-) => {.x = a.x-b.x, .y = a.y-b.y};
macro Point Point.neg(Point p) @operator_s(-) => {-p.x, -p.y};

macro Point Point.max(Point a, Point b) => {.x = max(a.x, b.x), .y = max(a.y, b.y)};
macro Point Point.min(Point a, Point b) => {.x = min(a.x, b.x), .y = min(a.y, b.y)};

macro bool Point.equals(Point a, Point b) @operator_s(==) => a.x == b.x && a.y == b.y;

// ---------------------------------------------------------------------------------- //
//                                    COLOR                                           //
// ---------------------------------------------------------------------------------- //

struct Color{
	char r, g, b, a;
}

macro Color uint.to_rgba(u)
{
	return {
		.r = (char)((u >> 24) & 0xff),
		.g = (char)((u >> 16) & 0xff),
		.b = (char)((u >> 8) & 0xff),
		.a = (char)((u >> 0) & 0xff)
	};
}


macro Color uint.@to_rgba($u)
{
	return {
		.r = (char)(($u >> 24) & 0xff),
		.g = (char)(($u >> 16) & 0xff),
		.b = (char)(($u >> 8) & 0xff),
		.a = (char)(($u >> 0) & 0xff)
	};
}

macro uint Color.to_uint(c) => c.r | (c.g << 8) | (c.b << 16) | (c.a << 24);

// ---------------------------------------------------------------------------------- //
//                                    SIZE                                            //
// ---------------------------------------------------------------------------------- //

struct Size {
	short min, max;
}

macro Size @grow() => {.min = 0, .max = 0};
macro Size @exact(short s) => {.min = s, .max = s};
macro Size @fit(short min = 0, short max = short.max) => {.min = min, .max = max};

macro bool Size.@is_grow(s) => (s.min == 0 && s.max == 0);
macro bool Size.@is_exact(s) => (s.min == s.max && s.min != 0);
macro bool Size.@is_fit(s) => (s.min != s.max);

macro Size Size.add(a, Size b) @operator_s(+) => {.min = a.min.sat_add(b.min), .max = a.max.sat_add(b.max)};
macro Size Size.sub(a, Size b) @operator_s(-) => {.min = a.min.sat_sub(b.min), .max = a.max.sat_sub(b.max)};

macro Size Size.combine(a, Size b) => {.min = max(a.min, b.min), .max = min(a.max, b.max)};
macro Size Size.comb_max(a, Size b) => {.min = max(a.min, b.min), .max = max(a.max, b.max)};
macro Size Size.comb_min(a, Size b) => {.min = min(a.min, b.min), .max = min(a.max, b.max)};

macro short Size.greater(a) => a.min > a.max ? a.min : a.max;
