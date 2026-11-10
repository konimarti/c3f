module c3f;
import c3::lexer, std::collections::list, std::io;

struct BraceAt
{
	sz first;         // the `if`, `else`, `while`, `for` or `foreach`
	sz open_after;    // the token the '{' follows: the ')' of the header, or `else`
	sz body;          // the first token of the body
	sz end;           // the ';' of the body
	sz close_after;   // the token the '}' follows: the ';', or a comment after it on its line
}

<* Can a body that starts with this token be put in braces without changing what it means? *>
fn bool can_brace_from(TokenType t) @local
{
	switch (t)
	{
		// nested control flow (a dangling `else`), a block, an empty statement; a `defer` belongs to the block around it
		case LBRACE: case IF: case ELSE: case FOR: case FOREACH: case FOREACH_R: case WHILE: case DO:
		case SWITCH: case EOS: case DEFER: case CASE: case DEFAULT:
			return false;
		default:
			return true;
	}
}

<* The ';' that ends the statement starting at `from`, or NO if it is not a plain one. *>
fn sz statement_end(Src* s, sz from) @local
{
	for (sz k = from; k != NO && k < s.len(); k = s.next_code(k))
	{
		Tok* t = &s.toks[k];
		if (t.keep || t.unterminated) return NO;
		if (t.type == EOS) return k;
		if (t.type == LBRACE && t.brace == BLOCK) return NO;   // a lambda
		if (is_closer(t.type)) return NO;
		if (!is_opener(t.type)) continue;
		if (t.match == NO) return NO;
		k = t.match;
	}
	return NO;
}

<*
 Used by `wrap_rewrite`: the single statement after an `if`, `else`, `while`, `for` or `foreach`
 cannot move to the next line without braces, so one that is too long for its line gets them,
 and its body goes on a line of its own. This adds tokens (a '{' and a '}' for each); the result is
 checked to be the input with just these tokens added. If nothing needs braces or the check fails,
 `text` itself is returned.
*>
fn String brace_long_bodies(String text, Config* cfg)
{
	if (cfg.max_line_length == 0) return text;
	Src s;
	s.init(text);
	if (s.bom || s.len() == 0 || s.unbalanced.len() > 0) return text;
	List{BraceAt} found;
	found.tinit();
	for (sz i = 0; i < s.len(); i++)
	{
		Tok* t = &s.toks[i];
		if (!t.code || t.keep) continue;
		sz header_end = NO;
		if (t.type == ELSE)
		{
			header_end = i;
		}
		else if (t.type == IF || t.type == WHILE || t.type == FOR || t.type == FOREACH || t.type == FOREACH_R)
		{
			sz p = s.next_code(i);
			if (s.type_at(p) == LPAREN) header_end = s.toks[p].match;
		}
		if (header_end == NO) continue;
		sz body = s.next_code(header_end);
		if (body == NO || !can_brace_from(s.toks[body].type)) continue;
		sz end = statement_end(&s, body);
		if (end == NO) continue;
		// the width of the statement on one line, with what stands before it on its line
		bool plain = true;
		sz width = text_width(s.text[s.line_start[t.line - 1]:t.start - s.line_start[t.line - 1]], 0, cfg.tab_width);
		for (sz k = i; k <= end; k++)
		{
			Tok* c = &s.toks[k];
			if (!c.code || c.text.contains("\n"))
			{
				plain = false;
				break;
			}
			if (k > i) width += c.nl > 0 ? 1 : c.start - (s.toks[k - 1].start + s.toks[k - 1].text.len);
			width = text_width(c.text, width, cfg.tab_width);
		}
		if (!plain || width <= cfg.max_line_length) continue;
		// a comment after the ';' on its line stays there: the '}' comes after it
		sz close_after = end;
		for (sz k = end + 1; k < s.len() && !s.toks[k].code && s.toks[k].nl == 0 && !s.toks[k].text.contains("\n"); k++) close_after = k;
		found.push({ i, header_end, body, end, close_after });
		i = close_after;
	}
	if (!found.len()) return text;
	String nl = s.crlf ? "\r\n" : "\n";
	DString d;
	d.tinit();
	sz from = 0;
	foreach (b : found)
	{
		sz close = s.toks[b.close_after].start + s.toks[b.close_after].text.len;
		sz semi = s.toks[b.end].start + s.toks[b.end].text.len;
		d.append(s.text[from:s.toks[b.first].start - from]);
		// the statement is written on one line again, to be wrapped anew inside its block
		append_joined(&d, &s, b.first, b.open_after);
		d.append(" {");
		d.append(nl);
		append_joined(&d, &s, b.body, b.end);
		d.append(s.text[semi:close - semi]);
		d.append(nl);
		d.append("}");
		from = close;
	}
	d.append(s.text[from..]);
	String out = d.str_view();
	// the input with a '{' after each header and a '}' after each body, and nothing else
	Lexer lx;
	lx.init(out);
	sz at = 0;
	foreach (b : found)
	{
		for (; at <= b.open_after; at++) if (!expect(&lx, s.toks[at].type, s.toks[at].text)) return text;
		if (!expect(&lx, LBRACE, "{")) return text;
		for (; at <= b.close_after; at++) if (!expect(&lx, s.toks[at].type, s.toks[at].text)) return text;
		if (!expect(&lx, RBRACE, "}")) return text;
	}
	for (; at < s.len(); at++) if (!expect(&lx, s.toks[at].type, s.toks[at].text)) return text;
	// the lexer reports the end of the input as io::EOF; anything else is an error
	Token? end = lx.next();
	if (catch err = end) return err == io::EOF ? out : text;
	return end.type == EOF ? out : text;
}

fn bool expect(Lexer* lx, TokenType type, String text) @local
{
	Token? t = lx.next();
	if (catch t) return false;
	return t.type == type && t.text == text;
}

<* The text of tokens a to b, with a gap that holds a line break written as one space. *>
fn void append_joined(DString* d, Src* s, sz a, sz b) @local
{
	for (sz k = a; k <= b; k++)
	{
		if (k > a) d.append(s.toks[k].nl > 0 ? " " : s.text[s.toks[k - 1].start + s.toks[k - 1].text.len:s.toks[k].start - s.toks[k - 1].start - s.toks[k - 1].text.len]);
		d.append(s.toks[k].text);
	}
}
