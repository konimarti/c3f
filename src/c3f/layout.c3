module c3f;
import c3::lexer, std::collections::list;

<* Indentation of an output line: `levels` indent units, then `extra` copied whitespace. *>
struct Indent
{
	sz     levels;
	String extra;
}

fn Indent Indent.deeper(self, sz by = 1) => { self.levels + by, self.extra };

<* What is written in the gap before a token. *>
struct Out
{
	sz     nl;          // newlines (0: the token stays on the line)
	Indent indent;      // when nl > 0, or for the first token
	String spacing;      // when nl == 0
	bool   verbatim;    // copy the source gap
	bool   anchor;      // alignment candidate (decided in align.c3)
	bool   cont;        // a continuation line: it belongs to the statement above
	sz     line_tok;    // first token of the output line
	sz     col;         // output column where the token starts (before alignment)
	String[] pieces;    // a string literal written as several (`wrap-strings`): the text of each
	Indent piece_indent; // the indent of the lines after the first piece
}

enum FrameKind : char { ROOT, BRACE, CT, CASE }

<* An indentation level: a '{' block, a compile-time block or a case region. *>
struct Frame
{
	FrameKind kind;
	sz        opener;     // '{', $if/$for/$foreach/$switch, or the case label
	sz        owner;      // CASE: the switch '{' or $switch
	sz        anchor;     // the '{' whose direct content is indented here (NO at top level)
	Indent    base;       // indent of the opener's line
	Indent    content;    // indent of lines directly inside
	Indent    head;       // indent of the last line that started a statement
	String    head_src;   // that line's source indentation
	bool      has_head;
}

struct Fmt
{
	Src*        src;
	Config*     cfg;
	List{Out}   out;
	List{Frame} frames;
	List{sz}    after;    // while aligning: output column after each token
	WrapMemo*   memo;     // breaks of statements wrapped before (null: none kept)
}

fn void Fmt.init(&self, Src* src, Config* cfg)
{
	*self = { .src = src, .cfg = cfg };
	self.out.tinit();
	self.frames.tinit();
}

fn Tok* Fmt.tok(&self, sz i) @inline => &self.src.toks[i];

// ---- line breaks ---------------------------------------------------------------------------

fn void Fmt.breaks(&self)
{
	Src* s = self.src;
	Config* c = self.cfg;
	self.out.clear();
	// every attempt starts from the source's line breaks (wrapping changes Tok.nl)
	foreach (&t : s.toks) t.nl = t.src_nl;
	for (sz i = 0; i < s.len(); i++) self.out.push({ .nl = i == 0 ? 0 : s.toks[i].nl });
	for (sz i = 1; i < s.len(); i++)
	{
		Tok* t = &s.toks[i];
		Out* o = &self.out[i];
		if (t.keep)
		{
			o.verbatim = true;
			continue;
		}
		if (o.nl > c.max_blank_lines + 1) o.nl = c.max_blank_lines + 1;
		if (o.nl > 1 && c.trim_block_blanks && (s.toks[i - 1].type == LBRACE || t.type == RBRACE)) o.nl = 1;
		if (s.toks[i - 1].type == LINE_COMMENT && o.nl == 0) o.nl = 1;
	}
	for (sz i = 0; i < s.len(); i++)
	{
		Tok* t = &s.toks[i];
		switch (t.type)
		{
			case LBRACE: self.brace_breaks(i);
			case ELSE: self.else_break(i);
			default:
		}
		if (c.decl_spacing == ONE) self.decl_break(i);
	}
	// the spacing rules look at line breaks: let them see these, as the next run will
	for (sz i = 1; i < s.len(); i++) s.toks[i].nl = self.out[i].nl;
}

fn bool Fmt.fixed(&self, sz i) @inline => i >= self.src.len() || self.src.toks[i].keep;

fn void Fmt.brace_breaks(&self, sz o)
{
	Src* s = self.src;
	Tok* t = &s.toks[o];
	if (t.brace != BLOCK && t.brace != BODY) return;
	sz m = t.match;
	if (m == NO || o == 0 || self.fixed(o) || self.fixed(m)) return;
	bool content = m > o + 1;
	bool multi = s.toks[m].line > t.line || (content && t.brace == BLOCK && self.cfg.one_line_blocks == EXPAND);
	if (!multi) return;
	// a lambda body or a block inside an expression keeps its brace where it is
	bool in_expression = t.encl != NO && s.toks[t.encl].type != LBRACE;
	if (in_expression || s.is_lambda_body(o))
	{
		// nothing
	}
	else if (self.cfg.brace_style == ALLMAN || (self.cfg.brace_style == LINUX && s.is_function_body(o)))
	{
		if (self.out[o].nl == 0) self.out[o].nl = 1;
	}
	else if (self.out[o].nl > 0 && !is_comment_type(s.toks[o - 1].type) && !s.starts_statement(o))
	{
		self.out[o].nl = 0;
	}
	if (!content) return;
	// the content starts on a line of its own; a comment after the '{' stays on its line,
	// unless code follows it there (`{ /* c */ x;`: the block would not open)
	sz k = o + 1;
	while (k < m && !s.toks[k].code && self.out[k].nl == 0) k++;
	bool code_follows = k == o + 1 || (k < m && self.out[k].nl == 0);
	if (self.out[o + 1].nl == 0 && code_follows && !self.fixed(o + 1)) self.out[o + 1].nl = 1;
	if (self.out[m].nl == 0) self.out[m].nl = 1;
}

fn void Fmt.else_break(&self, sz e)
{
	Src* s = self.src;
	if (e == 0 || self.fixed(e) || s.toks[e - 1].type != RBRACE) return;
	// `if (x) { a; } else { b; }` on one line stays as it is (unless the block was just expanded)
	sz open = s.toks[e - 1].match;
	if (open == NO || (s.toks[open].line == s.toks[e - 1].line && self.out[e - 1].nl == 0)) return;
	ElseStyle style = self.cfg.else_style;
	if (style == FOLLOW) style = self.cfg.brace_style == ALLMAN ? ElseStyle.OWN_LINE : ElseStyle.CUDDLE;
	if (style == OWN_LINE && self.out[e].nl == 0) self.out[e].nl = 1;
	if (style == CUDDLE) self.out[e].nl = 0;
}

<* At least one blank line after a top-level function or type body. *>
fn void Fmt.decl_break(&self, sz i)
{
	Src* s = self.src;
	if (i == 0 || self.fixed(i) || self.out[i].nl != 1) return;
	Tok* p = &s.toks[i - 1];
	// (a closer's encl is its own opener: the opener tells whether it is at top level)
	if (p.type != RBRACE || p.match == NO || s.toks[p.match].encl != NO) return;
	BraceKind k = s.toks[p.match].brace;
	if (k != BLOCK && k != BODY) return;
	TokenType t = s.toks[i].type;
	if (t == ELSE || t == EOS || t == RBRACE || t == COMMA) return;
	self.out[i].nl = 2;
}

// ---- indentation and spacing ---------------------------------------------------------------

fn Frame* Fmt.top(&self) @inline => &self.frames[^1];

fn bool is_ct_end(TokenType t) => t == CT_ENDIF || t == CT_ENDFOR || t == CT_ENDFOREACH || t == CT_ENDSWITCH;

fn bool is_case_label(TokenType t) => t == CASE || t == DEFAULT || t == CT_CASE || t == CT_DEFAULT;

fn void Fmt.layout(&self)
{
	Src* s = self.src;
	Config* c = self.cfg;
	self.frames.clear();
	self.frames.push({ .kind = ROOT, .opener = NO, .owner = NO, .anchor = NO });
	sz col;
	for (sz i = 0; i < s.len(); i++)
	{
		Tok* t = &s.toks[i];
		Out* o = &self.out[i];
		bool line_start = i == 0 || o.nl > 0;

		// frames that end or change at this token
		bool closes, ct_else, case_line;
		if (t.type == RBRACE && t.match != NO)
		{
			while (self.top().kind == CASE && self.top().owner == t.match) self.frames.pop()!!;
			closes = self.unwind_to(BRACE, t.match);
		}
		else if (is_ct_end(t.type) && t.match != NO)
		{
			while (self.top().kind == CASE && self.top().owner == t.match) self.frames.pop()!!;
			closes = self.unwind_to(CT, t.match);
		}
		else if (t.type == CT_ELSE && t.match != NO)
		{
			ct_else = self.top().kind == CT && self.top().opener == t.match;
		}
		else if (is_case_label(t.type) && t.parent != NO)
		{
			while (self.top().kind == CASE && self.top().owner == t.parent) self.frames.pop()!!;
			case_line = self.top().opener == t.parent;
		}
		Frame* f = self.top();

		if (line_start)
		{
			o.line_tok = i;
			if (o.verbatim)
			{
				o.indent = { 0, s.line_indent(t.line) };
			}
			else if (self.flush_directive(i))
			{
				o.indent = {};
			}
			else if (closes || ct_else)
			{
				o.indent = f.base;
			}
			else if (case_line)
			{
				o.indent = f.content;
			}
			else
			{
				o.indent = self.indent_for(i, f);
			}
			col = self.indent_width(o.indent);
		}
		else
		{
			o.line_tok = self.out[i - 1].line_tok;
			if (!o.verbatim) self.space(i);
			col = text_width(o.verbatim ? s.gap(i) : o.spacing, col, c.tab_width);
		}
		o.col = col;
		// as written: the lines of a comment may move
		col = text_width(t.type == BLOCK_COMMENT || t.type == CONTRACT ? self.token_text(i) : t.text, col, c.tab_width);

		// frames that start at this token
		Indent line = self.out[o.line_tok].indent;
		if (closes)
		{
			self.frames.pop()!!;
		}
		else if (t.type == LBRACE && t.match != NO && self.opens_lines(i))
		{
			Indent content = t.is_switch && !c.case_indent ? line : line.deeper();
			self.frames.push({ .kind = BRACE, .opener = i, .owner = NO, .anchor = i, .base = line, .content = content });
		}
		else if (is_ct_open(t.type) && t.match != NO)
		{
			// a column-0 directive inside a block adds no level
			Indent content = self.flush_directive(i) ? f.content : self.ct_content(i, line);
			// the header line is the frame's head: its own continuation lines indent from it
			self.frames.push({ .kind = CT, .opener = i, .owner = NO, .anchor = f.anchor, .base = line, .content = content,
				.head = line, .head_src = s.indent_of(i), .has_head = true });
		}
		else if (case_line)
		{
			bool ct = t.type == CT_CASE || t.type == CT_DEFAULT;
			Indent content = ct ? self.ct_content(i, line) : line.deeper();
			self.frames.push({ .kind = CASE, .opener = i, .owner = t.parent, .anchor = f.anchor, .base = line,
				.content = content, .head = line, .head_src = s.indent_of(i), .has_head = true });
		}
	}
}

<*
 Is there a frame of this kind opened at `opener`? Then the frames above it end here as well
 (`{ $if } $endif`: the '}' ends the `$if` inside it). The frame itself is the top afterwards.
*>
fn bool Fmt.unwind_to(&self, FrameKind kind, sz opener)
{
	// frames are pushed in source order: below one opened before `opener` there is none of it
	for (sz k = self.frames.len() - 1; k > 0 && self.frames[k].opener >= opener; k--)
	{
		if (self.frames[k].kind != kind || self.frames[k].opener != opener) continue;
		while (self.frames.len() - 1 > k) self.frames.pop()!!;
		return true;
	}
	return false;
}

<* `$if`/`$else`/`$endif`… written at column 0 inside a block (keep mode): it stays there. *>
fn bool Fmt.flush_directive(&self, sz i)
{
	Src* s = self.src;
	Tok* t = &s.toks[i];
	if (self.cfg.ct_indent != KEEP || (i > 0 && self.out[i].nl == 0) || t.encl == NO) return false;
	if (!is_ct_open(t.type) && !is_ct_end(t.type) && t.type != CT_ELSE) return false;
	return s.indent_of(i).len == 0;
}

<*
 Content indent of a compile-time block whose header is token h on a line indented `line`:
 `keep` follows the source (is the first line of the body indented deeper than the header?).
*>
fn Indent Fmt.ct_content(&self, sz h, Indent line)
{
	switch (self.cfg.ct_indent)
	{
		case INDENT: return line.deeper();
		case FLUSH: return line;
		case KEEP:
			Src* s = self.src;
			// the body starts after the header's ':' (a header may go on over lines)
			sz body = h + 1;
			for (sz k = h + 1; k < s.len() && k != s.toks[h].match; k++)
			{
				Tok* t = &s.toks[k];
				if (t.encl != s.toks[h].encl) continue;
				if (t.label) body = k + 1;
				if (t.label || t.type == EOS || t.type == LBRACE) break;
			}
			// the first source line of the body at the header's own level (a line inside a
			// bracket opened in the body is indented by that bracket)
			for (sz k = body; k < s.len() && k != s.toks[h].match; k++)
			{
				Tok* t = &s.toks[k];
				if (is_opener(t.type) && t.match != NO && t.src_nl == 0)
				{
					k = t.match;
					continue;
				}
				// (a line kept as written does not move with the header: it says nothing)
				if (t.src_nl == 0 || t.encl != s.toks[h].encl || t.keep) continue;
				if (is_ct_end(t.type) || t.type == CT_ELSE) return line;
				sz tw = self.cfg.tab_width;
				bool deeper = text_width(s.indent_of(k), 0, tw) > text_width(s.indent_of(h), 0, tw);
				return deeper ? line.deeper() : line;
			}
			return line;
	}
}

<* Does the '{' at i end its line (a trailing comment after it does not count)? *>
fn bool Fmt.opens_lines(&self, sz i)
{
	Src* s = self.src;
	sz k = i + 1;
	while (k < s.len() && !s.toks[k].code && self.out[k].nl == 0) k++;
	return k < s.len() && self.out[k].nl > 0;
}

fn sz Fmt.indent_width(&self, Indent ind)
{
	sz unit = self.cfg.indent_style == TAB ? self.cfg.tab_width : self.cfg.indent_size;
	return text_width(ind.extra, ind.levels * unit, self.cfg.tab_width);
}

<* Indentation of a line starting with token i inside frame f. *>
fn Indent Fmt.indent_for(&self, sz i, Frame* f)
{
	Src* s = self.src;
	sz j = i;
	if (!s.toks[i].code)
	{
		// an own-line comment is indented like the code that follows it
		j = s.next_code(i);
		if (j == NO) return f.content;
		Tok* n = &s.toks[j];
		bool closes = (n.type == RBRACE || is_ct_end(n.type) || n.type == CT_ELSE) && n.match == f.opener;
		if (closes) return f.content;
		if (is_case_label(n.type) && n.parent != NO)
		{
			if (f.kind == CASE && f.owner == n.parent) return f.base;
			if (f.opener == n.parent) return f.content;
		}
	}
	Tok* t = &s.toks[j];
	sz p = s.prev_code(j);
	TokenType pt = s.type_at(p);
	bool head = t.encl == f.anchor && (p == NO || pt == EOS || pt == RBRACE || s.toks[p].label || p == f.anchor
		|| (pt == COMMA && f.anchor != NO && s.toks[f.anchor].brace != BLOCK) || pt == CT_ELSE || is_ct_end(pt));
	// `case X:` then `{` on its own line: at the case level or one deeper, as in the source
	if (head && f.kind == CASE && t.type == LBRACE && i == j && p != NO && s.toks[p].label)
	{
		sz tw = self.cfg.tab_width;
		bool deeper = text_width(s.indent_of(j), 0, tw) > text_width(f.head_src, 0, tw);
		return deeper ? f.content : f.base;
	}
	if (head)
	{
		// the line starts the statement (possibly after a comment on the line, which may begin
		// lines above: `/* … */ x`); its source indentation is that of the line's first token
		if (self.same_output_line(i, j))
		{
			f.head = f.content;
			f.head_src = s.indent_of(i);
			f.has_head = true;
		}
		return f.content;
	}
	Indent base = f.has_head ? f.head : f.content;
	if (t.type == LBRACE && (t.brace == BLOCK || t.brace == BODY) && i == j) return base;
	self.out[i].cont = true;
	// the members of a multi-line `faultdef` are one level in, like those of an enum body
	if (t.fault_member) return base.deeper();
	switch (self.cfg.continuation)
	{
		case KEEP:
			// relative to the line the statement started on (none: one level, as `tab` does)
			if (!f.has_head) nextcase TAB;
			return { base.levels, base.extra.tconcat(self.relative(s.indent_of(i), f.head_src)) };
		case ALIGN:
			sz o = t.encl;
			// (under the first token after the opener; not under a comment there, which aligning moves)
			if (o != NO && (s.toks[o].type == LPAREN || s.toks[o].type == LBRACKET) && o + 1 < i && self.out[o + 1].nl == 0
				&& s.toks[o + 1].code)
			{
				Indent line = self.out[self.out[o].line_tok].indent;
				sz pad = self.out[o + 1].col - self.indent_width(line);
				if (pad > 0) return { line.levels, line.extra.tconcat(spaces(pad)) };
			}
			nextcase TAB;
		case TAB:
			return is_closer(t.type) && i == j ? base : base.deeper();
	}
}

<* Are tokens i..j on one output line? *>
fn bool Fmt.same_output_line(&self, sz i, sz j)
{
	for (sz k = i + 1; k <= j; k++) if (self.out[k].nl > 0) return false;
	return true;
}

<* The extra indentation of source indent `line` over the head line's source indent `head`. *>
fn String Fmt.relative(&self, String line, String head)
{
	sz tw = self.cfg.tab_width;
	String extra;
	if (line.starts_with(head))
	{
		extra = line[head.len..];
	}
	else
	{
		sz w = text_width(line, 0, tw) - text_width(head, 0, tw);
		if (w <= 0) return "";
		extra = line.contains(" ") ? spaces(w) : tabs(w / tw);
	}
	// a head indented with spaces under tab indentation: the extra spaces become tabs (as wide)
	bool head_spaces = head.len > 0 && !head.contains("\t");
	if (self.cfg.indent_style == TAB && head_spaces && !extra.contains("\t"))
	{
		return tabs(extra.len / tw).tconcat(spaces(extra.len % tw));
	}
	return extra;
}

<* Decide the same-line gap before token i. *>
fn void Fmt.space(&self, sz i)
{
	Src* s = self.src;
	Config* c = self.cfg;
	Out* o = &self.out[i];
	String gap = s.gap(i);
	if (gap.contains("\n"))
	{
		o.spacing = " ";     // a line that was joined (brace or else style)
		return;
	}
	Space rule = s.space_rule(i, c);
	bool comment = is_comment_type(s.toks[i].type);
	// c3f_trailing_comment_spaces: a fixed distance to a trailing // comment
	if (s.toks[i].type == LINE_COMMENT && c.trailing_comment_spaces && c.align_comments != ALWAYS)
	{
		o.spacing = spaces(c.trailing_comment_spaces);
		return;
	}
	bool wide = gap.len >= 2 || gap.contains("\t");
	if (wide && (comment ? c.align_comments != OFF : c.align != OFF))
	{
		o.anchor = true;
		o.spacing = gap;
		return;
	}
	if (wide && rule == KEEP) rule = ONE;
	o.spacing = self.apply(i, rule, gap);
}

<* The text for a same-line gap; removing a space never merges two tokens (a space can always be added). *>
fn String Fmt.apply(&self, sz i, Space rule, String gap)
{
	Tok* a = self.tok(i - 1);
	Tok* b = self.tok(i);
	switch (rule)
	{
		case KEEP: return gap;
		case NONE: return gap.len == 0 || glue_safe(a.text, b.text, a.type, b.type) ? "" : " ";
		case ONE: return " ";
	}
}

// ---- text helpers --------------------------------------------------------------------------

<* Column after writing `text` from column `col` (tabs expand, UTF-8 counts characters, newlines restart). *>
fn sz text_width(String text, sz col, sz tab_width)
{
	foreach (ch : text)
	{
		switch
		{
			case ch == '\n': col = 0;
			case ch == '\t': col = (col / tab_width + 1) * tab_width;
			case (ch & 0xC0) == 0x80: break;
			default: col++;
		}
	}
	return col;
}

fn String spaces(sz n) => repeat(' ', n);
fn String tabs(sz n) => repeat('\t', n);

fn String repeat(char c, sz n)
{
	if (n <= 0) return "";
	DString d;
	d.tinit();
	d.append_char_repeat(c, n);
	return d.str_view();
}
