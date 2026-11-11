module c3f;
import c3::lexer, std::collections::list;

fn String Fmt.eol(&self)
{
	switch (self.cfg.end_of_line)
	{
		case KEEP: return self.src.crlf ? "\r\n" : "\n";
		case LF: return "\n";
		case CRLF: return "\r\n";
	}
}

fn String Fmt.indent_text(&self, Indent ind)
{
	if (self.cfg.indent_style == TAB) return tabs(ind.levels).tconcat(ind.extra);
	// spaces: expand the tabs of the copied part too
	sz w = self.indent_width(ind);
	return spaces(w);
}

<* Indent string of the output line holding token i. *>
fn String Fmt.line_text(&self, sz i)
{
	Out* first = &self.out[self.out[i].line_tok];
	if (first.verbatim) return self.src.line_indent(self.src.toks[self.out[i].line_tok].line);
	return self.indent_text(first.indent);
}

<*
 Token text as written. The inner lines of a multi-line comment or contract move with its
 first line, but only if every one of them starts with the old indentation.
*>
fn String Fmt.token_text(&self, sz i)
{
	Tok* t = &self.src.toks[i];
	if ((t.type != CONTRACT && t.type != BLOCK_COMMENT) || t.unterminated || !t.text.contains("\n")) return t.text;
	// only a line that starts with a token moves (`*/ x /*` starts inside the comment before)
	if (self.src.toks[self.out[i].line_tok].line != t.line) return t.text;
	String old = self.src.line_indent(t.line);
	String new = self.line_text(i);
	if (old == new) return t.text;
	DString d;
	d.tinit();
	sz from = 0;
	foreach (k, c : t.text)
	{
		if (c != '\n') continue;
		d.append(t.text[from..k]);
		String rest = t.text[k + 1..];
		from = k + 1;
		bool blank = rest.len == 0 || rest[0] == '\n' || rest[0] == '\r';
		if (blank) continue;
		if (!rest.starts_with(old)) return t.text;
		d.append(new);
		from += old.len;
	}
	d.append(t.text[from..]);
	return d.str_view();
}

fn void Fmt.newlines(&self, DString* d, sz count, sz after)
{
	String eol = self.eol();
	for (sz k = 0; k < count; k++)
	{
		// a line comment that kept its '\r' already ends the line half way
		bool cr = k == 0 && after != NO && self.src.toks[after].text.ends_with("\r");
		d.append(cr && eol == "\r\n" ? "\n" : eol);
	}
}

<* Write the result; `texts` receives each token's text as written (for verification). *>
fn String Fmt.emit(&self, List{String}* texts)
{
	Src* s = self.src;
	DString d;
	d.tinit();
	texts.clear();
	if (s.bom) d.append("\xEF\xBB\xBF");
	for (sz i = 0; i < s.len(); i++)
	{
		Out* o = &self.out[i];
		switch
		{
			case o.verbatim:
				String g = self.convert_eol(s.gap(i));   // (never the first token)
				// a token that kept its '\r' (an unterminated string) already ends the line half way
				if (g.starts_with("\r\n") && s.toks[i - 1].text.ends_with("\r")) g = g[1..];
				d.append(g);
			case i == 0: d.append(self.indent_text(o.indent));
			case o.nl > 0:
				self.newlines(&d, o.nl, i - 1);
				d.append(self.indent_text(o.indent));
			default: d.append(o.spacing);
		}
		String text = self.token_text(i);
		// the line breaks inside a comment follow end_of_line too (a string's are its value)
		if (is_comment_type(s.toks[i].type)) text = self.convert_eol(text);
		if (o.pieces.len)
		{
			// a string written as several literals, each after the first on a line of its own
			texts.push(o.pieces[0]);
			d.append(o.pieces[0]);
			foreach (p : o.pieces[1..])
			{
				self.newlines(&d, 1, i);
				d.append(self.indent_text(o.piece_indent));
				d.append(p);
			}
			continue;
		}
		texts.push(text);
		d.append(text);
	}
	sz last = s.len() - 1;
	String tail = s.gap(s.len());
	if (s.toks[last].keep || s.toks[last].unterminated)
	{
		d.append(self.convert_eol(tail));
	}
	else if (self.cfg.insert_final_newline || tail.contains("\n"))
	{
		self.newlines(&d, 1, last);
	}
	return d.str_view();
}

<* Line endings inside gaps that are copied as written follow end_of_line too. *>
fn String Fmt.convert_eol(&self, String gap)
{
	if (self.cfg.end_of_line == KEEP || !gap.contains("\n")) return gap;
	String lf = gap.treplace("\r\n", "\n");
	return self.cfg.end_of_line == LF ? lf : lf.treplace("\n", "\r\n");
}

<* Index of the first token that did not come back as written, or NO. *>
fn sz Fmt.verify(&self, String output, List{String}* texts)
{
	Src* s = self.src;
	if (s.bom) output = output[3..];
	Recovering lx;
	lx.init(output);
	sz k = 0;
	while (try t = lx.next())
	{
		if (t.type == EOF) break;
		if (k >= s.len()) return s.len() - 1;
		String[] pieces = self.out[k].pieces;
		if (pieces.len)
		{
			// one source string, several literals: they must stand for the same bytes
			if (!same_value(s.toks[k].text, pieces)) return k;
			foreach (i, p : pieces)
			{
				if (i > 0)
				{
					Token? more = lx.next();
					if (catch more) return k;
					t = more;
				}
				if (t.type != STRING || t.text != p) return k;
			}
			k++;
			continue;
		}
		if (t.type != s.toks[k].type || t.text != (*texts)[k]) return k;
		k++;
	}
	return k == s.len() ? NO : k;
}
