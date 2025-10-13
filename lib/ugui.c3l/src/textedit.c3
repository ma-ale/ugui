module ugui;

import grapheme;
import std::ascii;

struct TextEdit {
	char[] buffer;
	usz chars;
	usz cursor;
}

fn String TextEdit.to_string(&te) => (String)te.buffer[:te.chars];
fn String TextEdit.until_cursor(&te) => (String)te.buffer[:te.cursor];
fn String TextEdit.from_cursor(&te) => (String)te.buffer[te.cursor..];

// implement text editing operations on the buffer
// returns true if the buffer is full
fn bool Ctx.text_edit(&ctx, TextEdit* te)
{
	String in = ctx.get_keys();
	ModKeys mod = ctx.get_mod();
	usz free = te.buffer.len - te.chars;
	usz after = te.chars - te.cursor;

	// append text input to the buffer
	if (in.len <= free) {
		// make space
		te.buffer[te.cursor+in.len : after] = te.buffer[te.cursor : after];
		// insert characters
		te.buffer[te.cursor : in.len] = in[..];
		// increment characters and cursor
		te.chars += in.len;
		te.cursor += in.len;
		free -= in.len;
	} else {
		return true;
	}

	// handle modkeys
	if (te.chars) {
		// handle backspace and delete
		if (mod.bkspc) {
			if (te.cursor > 0) {
				// TODO: only delete until punctuation
				usz how_many = mod & KMOD_CTRL ? te.until_cursor().prev_word_off() : te.until_cursor().prev_char_off();
				te.buffer[te.cursor-how_many : after] = te.buffer[te.cursor : after];
				te.cursor -= how_many;
				te.chars -= how_many;
				free += how_many;
			}
		}
		if (mod.del) {
			if (after > 0 && te.cursor < te.chars) {
				usz how_many = mod & KMOD_CTRL ? te.from_cursor().next_word_off() : te.from_cursor().next_char_off();
				te.buffer[te.cursor : after] = te.buffer[te.cursor+how_many : after];
				te.chars -= how_many;
				after -= how_many;
				free += how_many;
			}
		}

		// handle arrow keys
		if (mod.left) {
			if (te.cursor > 0) {
				usz how_many = mod & KMOD_CTRL ? te.until_cursor().prev_word_off() : te.until_cursor().prev_char_off();
				te.cursor -= how_many;
				after += how_many;
			}
		}
		if (mod.right) {
			if (after > 0) {
				usz how_many = mod & KMOD_CTRL ? te.from_cursor().next_word_off() : te.from_cursor().next_char_off();
				te.cursor += how_many;
				after -= how_many;
			}
		}
		// FIXME: this still doesn't work
		if (mod.up) {
			// back up to previous line
			if (te.cursor > 0) {
				usz curr_line_start = te.until_cursor().rindex_of_char('\n') ?? 0;
				usz prev_line_start = curr_line_start ? te.until_cursor()[..curr_line_start-1].rindex_of_char('\n') ?? 0 : 0;
				usz curr_line_off = te.cursor - curr_line_start;
				usz prev_line_len = curr_line_start - prev_line_start;
				te.cursor = prev_line_start + min(curr_line_off-1, prev_line_len);
				after = te.chars - te.cursor;
			}
		}
		if (mod.down) {
			// down to the next line
			if (after > 0) {
				usz curr_line_start = te.until_cursor().rindex_of_char('\n') ?? 0;
				usz curr_line_off = te.cursor - curr_line_start;
				usz next_line_start = te.from_cursor().index_of_char('\n') + te.cursor + 1 ?? te.chars;
				usz next_line_end = ((String)te.buffer[next_line_start..]).index_of_char('\n') + next_line_start ?? te.chars;
				usz next_line_len = next_line_end - next_line_start;
				te.cursor = next_line_start + min(curr_line_off, next_line_len);
				after = te.chars - te.cursor;
			}
		}
		
		// TODO: mod.home
		// TODO: mod.end
		// TODO: selection with shift+arrows
	}

	return free == 0;
}

macro isz char[].next_char_off(b) => grapheme::next_character_break_utf8(b.ptr, b.len);
macro isz char[].next_word_off(b) => grapheme::next_word_break_utf8(b.ptr, b.len);

fn isz char[].prev_char_off(b)
{
	foreach_r (off, c: b) {
		if (c & 0xC0 == 0x80) continue;
		return b.len - off;
	}
	return b.len;
}

fn isz char[].prev_word_off(b)
{
	for (isz off = b.len-1; off > 0;) {
		isz c_off = b[..off].prev_char_off();
		off -= c_off;
		if (ascii::is_punct(b[off]) || ascii::is_space(b[off])) return b.len - off - 1;
	}
	return b.len;
}