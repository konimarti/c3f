module c3f;
import c3::lexer, std::collections::list, std::collections::map, std::sort;

<* Source columns of every token (start, and end of the token before it), in one pass. *>
fn void Src.columns(&self, sz tab_width, List{sz}* start, List{sz}* prev_end)
{
	sz col;
	sz at;
	foreach (t : self.toks)
	{
		prev_end.push(col);
		col = text_width(self.text[at:t.start - at], col, tab_width);
		start.push(col);
		col = text_width(t.text, col, tab_width);
		at = t.start + t.text.len;
	}
}

<* Output column where token i - 1 ends, with the current spacing. *>
fn sz Fmt.prefix(&self, sz i)
{
	sz first = self.out[i].line_tok;
	if (self.after.len()) return i == first ? self.line_indent_width(first) : self.after[i - 1];
	sz col = self.line_indent_width(first);
	for (sz k = first; k < i; k++) col = self.advance(k, col);
	return col;
}

fn sz Fmt.line_indent_width(&self, sz first) @inline
{
	Out* fo = &self.out[first];
	return fo.verbatim ? text_width(self.src.line_indent(self.src.toks[first].line), 0, self.cfg.tab_width) : self.indent_width(fo.indent);
}

<* Column after token k, from column `col` before its gap. *>
fn sz Fmt.advance(&self, sz k, sz col) @inline
{
	if (k != self.out[k].line_tok) col = text_width(self.gap_text(k), col, self.cfg.tab_width);
	return text_width(self.src.toks[k].text, col, self.cfg.tab_width);
}

<* Measure the output line starting at token `first` into `after` (used by prefix while aligning). *>
fn void Fmt.measure_line(&self, sz first)
{
	sz col = self.line_indent_width(first);
	for (sz k = first; k < self.src.len() && (k == first || self.out[k].line_tok == first); k++)
	{
		col = self.advance(k, col);
		self.after[k] = col;
	}
}

<* Change the spacing before token k; the line is measured again if it changed. *>
fn void Fmt.set_spacing(&self, sz k, String spacing)
{
	if (self.out[k].spacing == spacing) return;
	self.out[k].spacing = spacing;
	self.measure_line(self.out[k].line_tok);
}

fn int token_class(TokenType t) @local
{
	if (is_type_token(t)) return -1;
	if (t == IDENT || t == CONST_IDENT || t == RPAREN || t == RBRACKET) return -2;
	return t.ordinal;
}

<* Can k line up with anchor a: the same kind of token, after the same kind of token? *>
fn bool Fmt.alike(&self, sz a, sz k)
{
	Src* s = self.src;
	if (s.toks[a].type != s.toks[k].type) return false;
	return token_class(s.toks[a - 1].type) == token_class(s.toks[k - 1].type);
}

<* Is token b on the output line right after the one of token a (no blank line, nothing moved)? *>
fn bool Fmt.next_line(&self, sz a, sz b)
{
	sz starts;
	for (sz m = a + 1; m <= b; m++)
	{
		if (self.out[m].nl > 1) return false;
		if (self.out[m].nl == 1) starts++;
	}
	return starts == 1;
}

fn String Fmt.gap_text(&self, sz k) @inline => self.out[k].verbatim ? self.src.gap(k) : self.out[k].spacing;

fn bool Fmt.same_line_gap(&self, sz k)
{
	Out* o = &self.out[k];
	return k > 0 && o.nl == 0 && !o.verbatim && !self.src.gap(k).contains("\n");
}

<*
 Columns that were aligned in the source stay aligned: a wide gap and the
 tokens at the same source column on the lines next to it form a group, and the group is
 re-padded by the largest shift of its members. A wide gap that lines up with nothing keeps
 its width (`c3f_align = off` spaces it normally).
*>
struct Anchor @local
{
	sz tok;
	sz col;    // source column
}

fn ulong at_key(sz line, sz col) @local => (ulong)line << 32 | (ulong)col;

fn void Fmt.align(&self)
{
	Src* s = self.src;
	sz tw = self.cfg.tab_width;
	List{sz} src_col;
	src_col.tinit();
	List{sz} src_prev_end;
	src_prev_end.tinit();
	s.columns(tw, &src_col, &src_prev_end);
	HashMap{ulong, sz} at;   // (line, source column) → token after a same-line gap
	at.tinit();
	List{Anchor} anchors;
	anchors.tinit();
	for (sz i = 1; i < s.len(); i++)
	{
		if (!self.same_line_gap(i) || s.gap(i).len == 0) continue;
		sz col = src_col[i];
		at.set(at_key(s.toks[i].line, col), i);
		if (self.out[i].anchor) anchors.push({i, col});
	}
	// left columns first, so that the prefix of a later column is final
	sort::mergesort(&anchors, fn int(Anchor x, Anchor y) => (int)(x.col - y.col));
	// output columns, kept up to date as gaps change
	self.after.tinit();
	for (sz i = 0; i < s.len(); i++) self.after.push(0);
	for (sz i = 0; i < s.len(); i++) if (self.out[i].line_tok == i) self.measure_line(i);
	defer self.after.clear();
	List{bool} done;
	done.tinit();
	for (sz i = 0; i < s.len(); i++) done.push(false);
	List{sz} group;
	group.tinit();
	foreach (an : anchors)
	{
		sz a = an.tok;
		if (done[a] || self.opens_aligned(a)) continue;
		group.clear();
		sz c = an.col;
		sz line = s.toks[a].line;
		sz edge = a;
		for (sz l = line - 1; l > 0; l--)
		{
			sz? k = at.get(at_key(l, c));
			if (catch k) break;
			if (!self.alike(a, k) || !self.next_line(k, edge) || self.continues(k, edge) || self.opens_aligned(k)) break;
			group.push(k);
			edge = k;
		}
		group.push(a);
		edge = a;
		for (sz l = line + 1; ; l++)
		{
			sz? k = at.get(at_key(l, c));
			if (catch k) break;
			if (!self.alike(a, k) || !self.next_line(edge, k) || self.continues(edge, k) || self.opens_aligned(k)) break;
			group.push(k);
			edge = k;
		}
		foreach (k : group) done[k] = true;
		sz shift = sz::min;
		foreach (k : group)
		{
			sz d = self.prefix(k) - src_prev_end[k];
			if (d > shift) shift = d;
		}
		foreach (k : group)
		{
			sz pad = c + shift - self.prefix(k);
			sz old = c - src_prev_end[k];
			self.set_spacing(k, pad == old ? s.gap(k) : spaces(pad));
		}
	}
	if (self.cfg.align == DECLS) self.align_decls();
	if (self.cfg.align_comments == ALWAYS) self.align_trailing_comments();
}

<*
 Is the line of token `down` inside a bracket opened on the line of token `up`? Then its
 indentation can depend on columns of that line (`c3f_continuation = align`): aligning the two
 would move it again on every run.
*>
fn bool Fmt.continues(&self, sz up, sz down)
{
	sz o = self.src.toks[self.out[down].line_tok].encl;
	return o != NO && self.out[o].line_tok == self.out[up].line_tok;
}

<*
 With `c3f_continuation = align`, does the line of token k open a bracket that the next line
 continues in? That line was placed under the bracket before alignment: moving its opener
 would leave it behind until the next run.
*>
fn bool Fmt.opens_aligned(&self, sz k)
{
	if (self.cfg.continuation != ALIGN) return false;
	sz m = k + 1;
	while (m < self.src.len() && self.out[m].nl == 0) m++;
	return m < self.src.len() && self.continues(k, m);
}

enum DeclKind : char @local { NONE, NAME, ASSIGN, ARROW }

<* On the output line starting at token a: the token to align (a declared name, an `=` or the `=>` of a one-line function), or NO. *>
fn sz Fmt.decl_anchor(&self, sz a, DeclKind* kind)
{
	Src* s = self.src;
	*kind = NONE;
	if (self.out[a].verbatim) return NO;
	sz end = a;
	while (end + 1 < s.len() && self.out[end + 1].nl == 0 && s.toks[end + 1].code) end++;
	if (s.toks[end].type != EOS) return NO;
	if (s.toks[a].type == FUNC || s.toks[a].type == MACRO)
	{
		// `fn int f() => 1;`: the top-level `=>`
		for (sz k = a + 1; k < end; k++)
		{
			if (s.toks[k].type != IMPLIES || s.toks[k].encl != s.toks[a].encl || s.toks[k].keep) continue;
			*kind = ARROW;
			return k;
		}
		return NO;
	}
	if (!is_type_token(s.toks[a].type) && s.toks[a].type != IDENT) return NO;
	for (sz k = a + 1; k < end; k++)
	{
		Tok* t = &s.toks[k];
		if (is_opener(t.type) || t.keep) return NO;
		Tok* p = &s.toks[k - 1];
		bool typed = is_type_token(p.type) || p.type == STAR || p.type == RBRACKET || p.type == RVEC || p.type == QUESTION;
		TokenType n = s.toks[k + 1].type;
		if (t.type == IDENT && typed && (n == EOS || n == EQ || n == AT_IDENT))
		{
			*kind = NAME;
			return k;
		}
		if (t.type == EQ)
		{
			*kind = ASSIGN;
			return k;
		}
	}
	return NO;
}

<* `c3f_align = decls`: names of consecutive declarations, and `=` of consecutive assignments, share a column. *>
fn void Fmt.align_decls(&self)
{
	Src* s = self.src;
	List{sz} run;
	run.tinit();
	DeclKind run_kind = NONE;
	sz run_line = NO;
	for (sz a = 0; a <= s.len(); a++)
	{
		bool line_start = a == s.len() || a == 0 || self.out[a].nl > 0;
		if (!line_start) continue;
		DeclKind kind;
		sz k = a < s.len() ? self.decl_anchor(a, &kind) : NO;
		bool continues = k != NO && kind == run_kind && run_line != NO && self.out[a].nl == 1
			&& self.indent_width(self.out[a].indent) == self.indent_width(self.out[run_line].indent);
		if (!continues)
		{
			self.pad_to_common_column(&run);
			run.clear();
			run_kind = kind;
		}
		if (k != NO) run.push(k);
		run_line = k != NO ? a : NO;
	}
}

<* `c3f_align_comments = always`: trailing comments on consecutive lines share one column. *>
fn void Fmt.align_trailing_comments(&self)
{
	Src* s = self.src;
	List{sz} run;
	run.tinit();
	for (sz i = 1; i <= s.len(); i++)
	{
		bool trailing = i < s.len() && s.toks[i].type == LINE_COMMENT && self.same_line_gap(i);
		if (i < s.len() && !trailing) continue;
		// a trailing comment continues the run if it is on the next output line
		if (run.len() && (!trailing || !self.next_line(run[^1], i)))
		{
			self.pad_to_common_column(&run);
			run.clear();
		}
		if (trailing) run.push(i);
	}
}

<* Give the gaps before the tokens of `run` one common column (one space past the longest prefix). *>
fn void Fmt.pad_to_common_column(&self, List{sz}* run)
{
	if (run.len() < 2) return;
	sz target;
	sz gap = self.src.toks[(*run)[0]].type == LINE_COMMENT ? max(self.cfg.trailing_comment_spaces, 1) : 1;
	foreach (k : *run) target = max(target, self.prefix(k) + gap - self.slack(k));
	if (self.cfg.max_line_length)
	{
		// not if that pushes a line past the limit
		foreach (k : *run)
		{
			// (the whole rest of the line moves: measure up to its last token)
			sz last = k;
			while (last + 1 < self.src.len() && self.out[last + 1].nl == 0) last++;
			if (self.after[last] + target - self.prefix(k) > self.cfg.max_line_length && self.prefix(k) + 1 < target) return;
		}
	}
	foreach (k : *run) self.set_spacing(self.lead(k), spaces(target - self.prefix(k) + self.slack(k)));
}

<* The token padded to align token k: the `*` of `int *p` (spaced off its type, glued to the name) moves with the name. *>
fn sz Fmt.lead(&self, sz k)
{
	sz l = k;
	while (self.src.toks[l - 1].type == STAR && self.out[l].spacing.len == 0 && self.out[l].nl == 0 && self.src.is_type_star(l - 1)) l--;
	return l != k && self.out[l].spacing.len > 0 && self.out[l].nl == 0 ? l : k;
}

<* The spacing before lead(k) that alignment may take back (it is part of prefix(k)). *>
fn sz Fmt.slack(&self, sz k) @inline => self.lead(k) == k ? 0 : self.out[self.lead(k)].spacing.len;
