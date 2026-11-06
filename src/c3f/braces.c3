module c3f;
import c3::lexer, std::collections::list;

struct BraceAt
{
	sz open_after;    // the token the '{' follows: the ')' of the header, or `else`
	sz body;          // the first token of the body
	sz close_after;   // the token the '}' follows: the ';' of the body, or a comment after it on its line
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
 Used by `wrap_fit`: the single statement after an `if`, `else`, `while`, `for` or `foreach`
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
		found.push({ header_end, body, close_after });
		i = close_after;
	}
	if (!found.len()) return text;
	String nl = s.crlf ? "\r\n" : "\n";
	DString d;
	d.tinit();
	sz from = 0;
	foreach (b : found)
	{
		sz open = s.toks[b.open_after].start + s.toks[b.open_after].text.len;
		sz close = s.toks[b.close_after].start + s.toks[b.close_after].text.len;
		d.append(s.text[from:open - from]);
		d.append(" {");
		d.append(nl);
		d.append(s.text[s.toks[b.body].start:close - s.toks[b.body].start]);
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
		for (; at <= b.open_after; at++) if (!same_next(&lx, s.toks[at])) return text;
		if (!inserted_next(&lx, LBRACE, "{")) return text;
		for (; at <= b.close_after; at++) if (!same_next(&lx, s.toks[at])) return text;
		if (!inserted_next(&lx, RBRACE, "}")) return text;
	}
	for (; at < s.len(); at++) if (!same_next(&lx, s.toks[at])) return text;
	if (try t = lx.next()) { if (t.type != EOF) return text; }
	return out;
}

fn bool same_next(Lexer* lx, Tok want) @local
{
	Token? t = lx.next();
	if (catch t) return false;
	return t.type == want.type && t.text == want.text;
}

fn bool inserted_next(Lexer* lx, TokenType type, String text) @local
{
	Token? t = lx.next();
	if (catch t) return false;
	return t.type == type && t.text == text;
}
