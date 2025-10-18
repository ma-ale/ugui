module ugui;

import grapheme;
import std::ascii;

struct TextEdit {
	char[] buffer;
	usz chars;
	usz cursor;
	usz sel_start, sel_end;
	bool selection;
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
		// if not already in selection update the selection start/end to the cursor positon
		if (!te.selection) {
			te.sel_start = te.sel_end = te.cursor;
		}

		// handle backspace and delete
		if (mod.bkspc) {
			if (te.cursor > 0) {
				usz how_many = te.how_many_bw(mod);
				te.buffer[te.cursor-how_many : after] = te.buffer[te.cursor : after];
				te.cursor -= how_many;
				te.chars -= how_many;
				free += how_many;
			}
		}
		if (mod.del) {
			if (after > 0 && te.cursor < te.chars) {
				usz how_many = te.how_many_fw(mod);
				te.buffer[te.cursor : after] = te.buffer[te.cursor+how_many : after];
				te.chars -= how_many;
				after -= how_many;
				free += how_many;
			}
		}

		// handle arrow keys
		if (mod.left) {
			if (te.cursor > 0) {
				usz how_many = te.how_many_bw(mod);
				te.cursor -= how_many;
				after += how_many;
				
				if (mod & KMOD_SHIFT) {
					te.selection = true;
					if (!te.selection) te.sel_start = te.cursor;
					te.sel_end = te.cursor;
				} else {
					te.selection = false;
				}
			}
		}
		if (mod.right) {
			if (after > 0) {
				usz how_many = te.how_many_fw(mod);
				te.cursor += how_many;
				after -= how_many;
				
				if (mod & KMOD_SHIFT) {
					te.sel_end = te.cursor-1;
					te.selection = true;
				} else {
					te.selection = false;
				}
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
	println("cursor: ", te.cursor, " start: ", te.sel_start, " end: ", te.sel_end);

	return free == 0;
}

fn usz TextEdit.how_many_fw(&te, ModKeys mod)
{
	if (mod & KMOD_CTRL) {
		return te.from_cursor().next_word_off();
	} else if (te.selection && !(mod & KMOD_SHIFT)) {
		// FIXME: +1 here is not correct, should use next_char_off()
		return te.sel_start > te.sel_end ? te.sel_end - te.sel_start + 1 : te.from_cursor().next_char_off();
	} else {
		return te.from_cursor().next_char_off();
	}
}

// how many characters to jump backwards (left arrow)
fn usz TextEdit.how_many_bw(&te, ModKeys mod)
{
	if (mod & KMOD_CTRL) {
		return te.until_cursor().prev_word_off();
	} else if (te.selection && !(mod & KMOD_SHIFT)){
		// FIXME: +1 here is not correct, should use prev_char_off()
		return te.sel_start < te.sel_end ? te.sel_end - te.sel_start + 1 : te.until_cursor().prev_char_off();
	} else {
		return te.until_cursor().prev_char_off();
	}
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