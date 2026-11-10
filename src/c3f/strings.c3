module c3f;
import c3::lexer, std::collections::list, std::sort;

// `c3f_line_breaks = wrap_rewrite`: a string literal that still runs past the limit after the
// statement was wrapped is written as several literals, which the compiler joins:
// "a long text" becomes "a long " "text". The split is chosen by a line-breaking
// dynamic program over the characters of the literal, like the one for statements but with its
// own costs: after a space is cheap, after punctuation dearer, inside a word dearest, never
// inside an escape sequence, a UTF-8 character or a printf conversion.

const float PIECE_COST = 3.0f;           // every extra piece
const float MID_WORD_COST = 20.0f;       // a break between two letters
const float OTHER_BREAK_COST = 8.0f;
const float PUNCT_BREAK_COST = 3.0f;
const float LEADING_SPACE_COST = 6.0f;   // a piece that starts with a space
const float SHORT_PIECE_COST = 10.0f;    // fewer than MIN_PIECE_UNITS characters
const float BALANCE_COST = 6.0f;         // times the square of the share of a line left empty: the pieces come out alike
const sz MIN_PIECE_UNITS = 3;

fn bool is_hex(char c) @local => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');

<*
 The characters of a string body that cannot be told apart: a character, an escape sequence, a UTF-8
 character. `ends` receives the offset after each. False if the body is not well formed.
*>
fn bool body_units(String body, List{sz}* ends) @local
{
	sz i = 0;
	while (i < body.len)
	{
		char c = body[i];
		sz n;
		switch
		{
			case c == '\\':
				if (i + 1 >= body.len) return false;
				switch (body[i + 1])
				{
					case 'a': case 'b': case 'e': case 'f': case 'n': case 'r': case 't': case 'v':
					case '\\': case '\'': case '"': case '0': n = 2;
					case 'x': n = 4;
					case 'u': n = 6;
					case 'U': n = 10;
					default: return false;
				}
				if (body[i + 1] == 'x' || body[i + 1] == 'u' || body[i + 1] == 'U')
				{
					if (i + n > body.len) return false;
					for (sz k = i + 2; k < i + n; k++) if (!is_hex(body[k])) return false;
				}
			case c < 0x80: n = 1;
			case c >= 0xC2 && c <= 0xDF: n = 2;
			case c >= 0xE0 && c <= 0xEF: n = 3;
			case c >= 0xF0 && c <= 0xF4: n = 4;
			default: return false;
		}
		if (i + n > body.len) return false;
		if (c >= 0x80) for (sz k = i + 1; k < i + n; k++) if ((body[k] & 0xC0) != 0x80) return false;
		i += n;
		ends.push(i);
	}
	return true;
}

fn bool is_word_unit(String u) @local
{
	char c = u[0];
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c >= 0x80;
}

<*
 The cost of ending a piece between unit p - 1 and unit p, or a negative number if that is not allowed.
*>
fn float break_cost(String prev, String next) @local
{
	float c;
	switch
	{
		case prev == " ": c = 0;
		case prev == "\\n": c = 0.5f;
		case prev.len == 1 && @ok(",;:.)/-".index_of_char(prev[0])): c = PUNCT_BREAK_COST;
		case is_word_unit(prev) && is_word_unit(next): c = MID_WORD_COST;
		default: c = OTHER_BREAK_COST;
	}
	if (next == " ") c += LEADING_SPACE_COST;
	return c;
}

<*
 Split the literal `text` (with its quotes) into pieces. `first_room` is the number of columns left for
 the characters of the first piece, `mid_room` the same for a line of its own, `tail` the width of what
 follows the literal on the last line. An empty list: the literal cannot be split to fit.
*>
fn List{String} plan_split(String text, sz first_room, sz mid_room, sz tail, sz tab_width) @local
{
	List{String} pieces;
	pieces.tinit();
	String body = text[1..^2];
	List{sz} ends;
	ends.tinit();
	if (!body_units(body, &ends)) return pieces;
	sz n = ends.len();
	if (n < 2) return pieces;
	// boundary p lies after unit p - 1; boundary 0 and n are the ends
	sz[] at = mem::talloc_array(sz, n + 1);
	at[0] = 0;
	foreach (k, e : ends) at[k + 1] = e;
	sz[] width = mem::talloc_array(sz, n + 1);
	width[0] = 0;
	for (sz k = 1; k <= n; k++) width[k] = width[k - 1] + text_width(body[at[k - 1]..at[k] - 1], 0, tab_width);
	// no break between a `%` and its conversion
	bool[] forbid = mem::talloc_array(bool, n + 1);
	foreach (&f : forbid) *f = false;
	for (sz k = 0; k < n; k++)
	{
		if (body[at[k]] != '%' || at[k + 1] != at[k] + 1) continue;
		sz j = k + 1;
		while (j < n && at[j + 1] == at[j] + 1)
		{
			char c = body[at[j]];
			bool length_modifier = c == 'h' || c == 'l' || c == 'L' || c == 'j' || c == 'z' || c == 't' || c == 'q';
			if (!length_modifier && ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '%')) break;
			j++;
		}
		for (sz p = k + 1; p <= j && p < n; p++) forbid[p] = true;
		k = j;
	}
	float[] best = mem::talloc_array(float, n + 1);
	sz[] from = mem::talloc_array(sz, n + 1);
	foreach (&b : best) *b = float::inf;
	best[0] = 0;
	for (sz j = 1; j <= n; j++)
	{
		bool last = j == n;
		if (!last && forbid[j]) continue;
		float bc = last ? 0 : break_cost(body[at[j - 1]..at[j] - 1], body[at[j]..at[j + 1] - 1]);
		for (sz i = 0; i < j; i++)
		{
			if (best[i] == float::inf || (i == 0 && last)) continue;
			sz room = i == 0 ? first_room : mid_room;
			if (last) room -= tail;
			sz w = width[j] - width[i];
			if (w > room) continue;
			float empty = room > 0 ? (float)(room - w) / (float)room : 0;
			float c = best[i] + bc + (last ? 0 : PIECE_COST) + BALANCE_COST * empty * empty;
			if (j - i < MIN_PIECE_UNITS) c += SHORT_PIECE_COST;
			if (c < best[j])
			{
				best[j] = c;
				from[j] = i;
			}
		}
	}
	if (best[n] == float::inf) return pieces;
	List{sz} cuts;
	cuts.tinit();
	for (sz j = n; j > 0; j = from[j]) cuts.push(j);
	sz i = 0;
	for (sz k = cuts.len(); k-- > 0;)
	{
		sz j = cuts[k];
		pieces.push("\"".tconcat(body[at[i]..at[j] - 1]).tconcat("\""));
		i = j;
	}
	return pieces;
}

<* The bytes a string body stands for; false if it is not well formed. *>
fn bool decode_body(String body, DString* out) @local
{
	List{sz} ends;
	ends.tinit();
	if (!body_units(body, &ends)) return false;
	sz from = 0;
	foreach (e : ends)
	{
		String u = body[from..e - 1];
		from = e;
		if (u[0] != '\\')
		{
			out.append(u);
			continue;
		}
		switch (u[1])
		{
			case 'a': out.append_char('\a');
			case 'b': out.append_char('\b');
			case 'e': out.append_char(0x1B);
			case 'f': out.append_char('\f');
			case 'n': out.append_char('\n');
			case 'r': out.append_char('\r');
			case 't': out.append_char('\t');
			case 'v': out.append_char('\v');
			case '0': out.append_char(0);
			case '\\': out.append_char('\\');
			case '\'': out.append_char('\'');
			case '"': out.append_char('"');
			default:
				// \xHH is one byte, \uHHHH and \UHHHHHHHH a code point
				uint v;
				foreach (h : u[2..])
				{
					v = v * 16 + (uint)(h <= '9' ? h - '0' : (h | 0x20) - 'a' + 10);
				}
				if (u[1] == 'x')
				{
					out.append_char((char)v);
				}
				else
				{
					out.append(string::tformat("\\u%08x", v));   // an escape is compared as a code point, never re-encoded
				}
		}
	}
	return true;
}

<* Do the pieces (literals with quotes) stand for the same bytes as `text`? Checked apart from how they were cut. *>
fn bool same_value(String text, String[] pieces)
{
	if (text.len < 2 || text[0] != '"' || text[^1] != '"') return false;
	DString want;
	want.tinit();
	if (!decode_body(text[1..^2], &want)) return false;
	DString got;
	got.tinit();
	foreach (p : pieces)
	{
		if (p.len < 2 || p[0] != '"' || p[^1] != '"') return false;
		if (!decode_body(p[1..^2], &got)) return false;
	}
	return got.str_view() == want.str_view();
}

<* The string at token k, where it may be written as several literals. *>
fn bool Fmt.splittable(&self, sz k)
{
	Src* s = self.src;
	Tok* t = &s.toks[k];
	String x = t.text;
	if (t.type != STRING || t.keep || t.unterminated || x.len < 4 || x[0] != '"' || x.starts_with("\"\"\"")) return false;
	if (x.contains("\t") || x.contains("\n")) return false;
	// the message of `$assert` / `$error` / `$echo`
	if (k > 0 && (s.toks[k - 1].type == CT_ERROR || s.toks[k - 1].type == CT_ECHO || s.toks[k - 1].message)) return false;
	// arguments of attributes, macros and compile-time directives, and the text of an `assert` condition
	for (sz o = t.encl; o != NO; o = s.toks[o].encl)
	{
		if (o == 0) break;
		Tok* p = &s.toks[o - 1];
		if (!p.code) return false;
		switch (p.type)
		{
			case AT_IDENT: case AT_TYPE_IDENT: case AT_CONST_IDENT: case ASM: case ASSERT: return false;
			case IDENT: if (p.text == "assert") return false;
			default: if (p.type.ordinal >= TokenType.CT_ASSERT.ordinal && p.type.ordinal <= TokenType.CT_VAARG.ordinal) return false;
		}
	}
	return true;
}

<* The indentation of the lines after the first piece of a string at token t on the line that starts with k. *>
fn Indent Fmt.piece_indent(&self, sz k, sz t)
{
	Src* s = self.src;
	Indent ind = t == k ? self.out[k].indent : self.out[k].indent.deeper();
	if (self.cfg.continuation == ALIGN)
	{
		sz o = s.toks[t].encl;
		if (o != NO && (s.toks[o].type == LPAREN || s.toks[o].type == LBRACKET) && o + 1 < t && self.out[o + 1].nl == 0 && s.toks[o + 1].code)
		{
			Indent line = self.out[self.out[o].line_tok].indent;
			sz pad = self.out[o + 1].col - self.indent_width(line);
			if (pad > 0) return { line.levels, line.extra.tconcat(spaces(pad)) };
		}
	}
	return ind;
}

<* Write the strings that still run past the limit as several literals. *>
fn void Fmt.split_strings(&self)
{
	if (self.cfg.line_breaks != WRAP_REWRITE || self.cfg.max_line_length == 0) return;
	Src* s = self.src;
	Config* c = self.cfg;
	sz tw = c.tab_width;
	for (sz k = 0; k < s.len(); k++)
	{
		if (self.out[k].line_tok != k) continue;
		sz e = k;
		bool plain = !self.out[k].verbatim;
		while (e + 1 < s.len() && self.out[e + 1].nl == 0 && !self.out[e + 1].verbatim) e++;
		while (e > k && !s.toks[e].code) e--;   // (a comment at the end of the line is not part of its length)
		for (sz j = k; j <= e; j++) if (!s.toks[j].code || s.toks[j].keep || self.out[j].verbatim) plain = false;
		if (!plain || self.end_col(e) <= c.max_line_length) continue;
		// the longest string of the line that can be split to fit
		List{sz} cands;
		cands.tinit();
		for (sz j = k; j <= e; j++) if (self.splittable(j)) cands.push(j);
		sort::mergesort(&cands, fn int(sz a, sz b, Src* s) => (int)(s.toks[b].text.len - s.toks[a].text.len), s);
		foreach (t : cands)
		{
			Indent ind = self.piece_indent(k, t);
			sz start = self.end_col(t) - text_width(s.toks[t].text, 0, tw);
			sz tail = self.end_col(e) - self.end_col(t);
			sz room = c.max_line_length - 2;
			List{String} pieces = plan_split(s.toks[t].text, room - start, room - self.indent_width(ind), tail, tw);
			if (pieces.len() < 2) continue;
			Out* o = &self.out[t];
			o.pieces = mem::talloc_array(String, pieces.len());
			foreach (n, p : pieces) o.pieces[n] = p;
			o.piece_indent = ind;
			if (self.memo) self.memo.wrapped++;
			break;
		}
	}
}
