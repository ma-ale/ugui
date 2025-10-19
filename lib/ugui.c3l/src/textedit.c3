module ugui;

import ugui::textedit::te;

struct TextEdit {
	char[] buffer;
	usz chars;
	usz cursor;
	isz sel_len;
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

	te.insert_utf8(in);


	// handle backspace and delete
	if (mod.bkspc) {
		te.remove_character(false);
	}
	if (mod.del) {
		te.remove_character(true);
	}

	// handle arrow keys
	if (mod.left) {
		te.move_cursor(false, !!(mod & KMOD_SHIFT));
	}
	if (mod.right) {
		te.move_cursor(true, !!(mod & KMOD_SHIFT));
	}

	// TODO: up, down
	// TODO: mod.home
	// TODO: mod.end
	// TODO: selection with shift+arrows

	println("cursor: ", te.cursor, " sel_len: ", te.sel_len);
	return te.chars < te.buffer.len;
}

module ugui::textedit::te;

import std::core::string;

// returns the offset of the next codepoint in the buffer from the cursor
fn usz TextEdit.next_char_off(&te)
{
	usz len = min(te.chars - te.cursor, 4);
	if (len == 0) return len;
	conv::utf8_to_char32(&te.buffer[te.cursor], &len)!!;
	return len;
}

// returns the offset of the previous codepoint in the buffer from the cursor
fn usz TextEdit.prev_char_off(&te)
{
	if (te.cursor == 0) return 0;
	String b = (String)te.buffer[..te.cursor];
	usz len;
	foreach_r (off, c: b) {
		if (c & 0xC0 == 0x80) continue;
		len = b.len - off;
		break;
	}
	// verify the utf8 character
	conv::utf8_to_char32(&b[te.cursor - len], &len)!!;
	return len;
}

// moves the cursor forwards or backwards by one codepoint without exiting the bounds, if select is
// true also change the selection width
fn void TextEdit.move_cursor(&te, bool forward, bool select)
{
	// in selection but trying to move without selecting, snap the cursor and reset selection
	if (te.sel_len != 0 && !select) {
		if (te.sel_len > 0 && forward) {
			// selection is in front of the cursor and trying to move right, snap the cursor to the
			// end of selection
			te.cursor += te.sel_len;
		} else if (te.sel_len < 0 && !forward) {
			// selection is behind the cursor and trying to move left, snap the cursor to the start
			// of selection
			te.cursor += te.sel_len;
		}
		te.sel_len = 0;

	} else {
		isz off = forward ? te.next_char_off() : -te.prev_char_off();
		if (te.cursor + off < 0 || te.cursor + off > te.chars) return;
		te.cursor += off;
		// if trying to select increment selection width
		if (select) {
			te.sel_len -= off;
		}
	}
}

// set the cursor to the exact offset provided, the selection flags controls wether the selection has
// expanded or rese
fn void TextEdit.set_cursor(&te, usz cur, bool select)
{
	if (!select) te.sel_len = 0;
	if (cur == te.cursor) return;

	usz prev_cur = te.cursor;
	te.cursor = cur;
	if (select) {
		te.sel_len += prev_cur - cur;
	}
}

fn void TextEdit.delete_selection(&te)
{
	if (te.sel_len == 0) return;

	usz start = te.sel_len > 0 ? te.cursor : te.cursor + te.sel_len;
	usz end   = te.sel_len > 0 ? te.cursor + te.sel_len : te.cursor;
	usz len = te.chars - end;

	te.buffer[start:len] = te.buffer[end:len];
	te.cursor -= te.sel_len < 0 ? -te.sel_len : 0;
	te.chars -= te.sel_len < 0 ? -te.sel_len : te.sel_len;
	te.sel_len = 0;
}

// removes the character before or after the cursor
fn void TextEdit.remove_character(&te, bool forward)
{
	// if there is a selection active then delete that selection
	if (te.sel_len) {
		te.delete_selection();
		return;
	}

	if (te.chars == 0) return;
	if (forward) {
		usz rem = te.chars - te.cursor;
		if (rem > 0) {
			usz len = te.next_char_off();
			te.buffer[te.cursor:rem-len] = te.buffer[te.cursor+len:rem-len];
			te.chars -= len;
		}
	} else {
		if (te.cursor > 0) {
			usz len = te.prev_char_off();
			te.buffer[te.cursor-len:te.chars-te.cursor] = te.buffer[te.cursor:te.chars-te.cursor];
			te.chars -= len;
			te.cursor -= len;
		}
	}
}

// insert a character at the cursor and update the cursor
fn void TextEdit.insert_character(&te, uint cp)
{
	char[4] b;
	usz len = conv::char32_to_utf8(cp, b[..])!!;
	te.insert_utf8((String)b[:len]);
}

fn void TextEdit.insert_utf8(&te, String s)
{
	if (s.len == 0) return;
	if (s.len + te.chars > te.buffer.len) return;

	te.delete_selection();
	te.buffer[te.cursor+s.len : te.chars-te.cursor] = te.buffer[te.cursor : te.chars-te.cursor];
	te.buffer[te.cursor : s.len] = s[..];
	te.chars += s.len;
	te.cursor += s.len;
}