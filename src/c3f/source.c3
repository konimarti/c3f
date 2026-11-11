module c3f;
import c3::lexer, std::collections::list;

const sz NO = -1;

<* What a '{' opens, decided from the tokens before it. *>
enum BraceKind : char
{
	NONE,      // not a '{'
	BLOCK,     // statements: function, if/while/for/switch body, bare block
	BODY,      // struct/union/enum/bitstruct/interface/constdef members
	INIT,      // initializer list or anything else
	GENERIC,   // List{int}
}

struct Tok
{
	TokenType type;
	String    text;
	sz      start;       // byte offset in the source
	sz      line;        // 1-based line of the first byte
	sz      nl;          // newlines in the gap before this token (wrapping may change it)
	sz      src_nl;      // as in the source
	sz      match;       // matching bracket, $end keyword or $if of an $else; NO if none
	sz      encl;        // innermost bracket open at the gap before this token (a closer: its own opener); NO at top level
	sz      parent;      // for case/default and $case/$default: the switch '{' or $switch; else NO
	int     prev, next;  // the nearest code tokens before and after (comments skipped); NO if none
	int     row;         // the first token of its source line
	BraceKind brace;
	bool      is_switch;   // '{' of a switch, or a $switch
	bool      label;       // ':' that ends a case label or a compile-time header
	bool      ternary;     // the '?' (or '???') and ':' of a ternary `c ? a : b`
	bool      message;     // the ':' before the message of `$assert cond : "message"`
	bool      fault_member; // part of a `faultdef … ;` statement: its members are indented
	bool      keep;        // the gap before this token is copied as written
	bool      code;        // not a comment or contract
	bool      unterminated;
	bool      cut;         // the first token after a damaged place: what comes before is not part of its statement or brackets
	bool      dangling;    // a '{' left open by a raw string or comment that is not closed: no partner, but it still indents
	bool      damaged;     // a raw string, comment or doc comment that is never closed
}

struct Src
{
	String     text;
	List{Tok}  toks;
	List{sz} line_start;    // byte offset of line n+1
	bool       crlf;
	bool       bom;
	List{char} memo;          // cached answers of is_cast_close / is_type_star
	List{Damage} unbalanced;  // brackets without a partner: tokens tok..last are kept as written
	List{Damage} broken;      // unterminated raw strings and comments, cut at the next top-level declaration
}

struct Damage
{
	sz tok;    // the bracket without a partner
	sz last;   // the last token kept as written because of it
	String cause;   // "" for a bracket; else what is wrong with the token itself
	sz line;        // the line of the last place kept
}

fn bool is_comment_type(TokenType t) => t == LINE_COMMENT || t == BLOCK_COMMENT || t == CONTRACT;
fn bool is_opener(TokenType t) => t == LPAREN || t == LBRACKET || t == LBRACE || t == LVEC;
fn bool is_closer(TokenType t) => t == RPAREN || t == RBRACKET || t == RBRACE || t == RVEC;

fn TokenType closer_of(TokenType t)
{
	switch (t)
	{
		case LPAREN: return RPAREN;
		case LBRACKET: return RBRACKET;
		case LBRACE: return RBRACE;
		default: return RVEC;
	}
}

fn bool is_base_type(TokenType t)
{
	switch (t)
	{
		case VOID: case BOOL: case CHAR: case ICHAR: case SHORT: case USHORT: case INT: case UINT:
		case LONG: case ULONG: case INT128: case UINT128: case FLOAT: case DOUBLE: case FLOAT16:
		case BFLOAT: case FLOAT128: case IPTR: case UPTR: case ISZ: case USZ: case FAULT: case ANY:
		case TYPEID:
			return true;
		default:
			return false;
	}
}

fn bool is_type_token(TokenType t) => is_base_type(t) || t == TYPE_IDENT || t == CT_TYPE_IDENT || t == AT_TYPE_IDENT;

<* Lex `text` and compute all structure. The tokens' text slices point into `text`. *>
fn void Src.init(&self, String text)
{
	*self = {};
	if (text.starts_with("\xEF\xBB\xBF"))
	{
		self.bom = true;
		text = text[3..];
	}
	self.text = text;
	self.line_start.push(0);
	foreach (i, c : text)
	{
		if (c != '\n') continue;
		self.line_start.push(i + 1);
		if (self.line_start.len() == 2) self.crlf = i > 0 && text[i - 1] == '\r';
	}
	Recovering lx;
	lx.init(text);
	sz last_code = NO;
	bool in_faultdef;
	bool after_cut;
	while (try t = lx.next())
	{
		if (t.type == EOF) break;
		sz i = self.toks.len();
		bool code = !is_comment_type(t.type);
		if (t.type == FAULTDEF) in_faultdef = true;
		self.toks.push({
			.type = t.type, .text = t.text, .start = t.offset, .line = t.ln, .nl = t.nl_before, .src_nl = t.nl_before,
			.match = NO, .encl = NO, .parent = NO, .code = code, .unterminated = t.unterminated, .fault_member = in_faultdef,
			.prev = (int)last_code, .next = (int)NO, .row = (int)(i == 0 || t.nl_before > 0 ? i : self.toks[i - 1].row) });
		if (after_cut)
		{
			// the damaged place ends where this line starts: its gap is kept as written
			self.toks[i].cut = true;
			self.toks[i].keep = true;
			in_faultdef = false;
			after_cut = false;
		}
		String cause = unterminated_cause(&t);
		if (cause.len)
		{
			self.toks[i].damaged = true;
			self.broken.push({ .tok = i, .last = i, .cause = cause, .line = lx.last_line });
			after_cut = lx.cut;
		}
		if (t.type == EOS) in_faultdef = false;
		if (!code) continue;
		// this is the next code token of the last one and of the comments after it
		for (sz k = last_code == NO ? 0 : last_code; k < i; k++) self.toks[k].next = (int)i;
		last_code = i;
	}
	self.keep_cut_contracts();
	// here, in the caller's scope (temp memory of a wrap's @pool would not outlive it)
	self.init_memo();
	self.match_brackets();
	self.classify_braces();
	self.match_ct();
	self.mark_labels();
	self.mark_ternaries();
	self.mark_off_regions();
}

// c3c reads a contract from its first `@name` line on as code, so its closing `*>` inside a
// string there does not end it, while the lexer ends it there and lexes the rest as code: such
// a contract, and the tokens made of the rest of it, are kept as written.
fn void Src.keep_cut_contracts(&self)
{
	for (sz i = 0; i < self.len(); i++)
	{
		if (self.toks[i].type != CONTRACT || self.toks[i].unterminated) continue;
		sz end = contract_end(self.text, self.toks[i].start);
		if (end <= self.end(i)) continue;
		sz k = i;
		while (k + 1 < self.len() && self.toks[k + 1].start < end) k++;
		self.keep_range(i, k + 1);
		i = k;
	}
}

<* Where c3c ends the contract that starts at `from` (with its `<*`). *>
fn sz contract_end(String s, sz from) @local
{
	bool code;
	bool line_start = true;
	sz k = from + 2;
	while (k < s.len)
	{
		char c = s[k];
		if (c == '*' && k + 1 < s.len && s[k + 1] == '>') return k + 2;
		if (code && (c == '"' || c == '\'' || c == '`'))
		{
			k = literal_end(s, k);
			line_start = false;
			continue;
		}
		if (line_start && c == '@' && k + 1 < s.len && s[k + 1] >= 'a' && s[k + 1] <= 'z') code = true;
		line_start = c == '\n' || (line_start && (c == ' ' || c == '\t' || c == '\r'));
		k++;
	}
	return s.len;
}

<* The end of the string, char or raw string literal at k ("…" and '…' end at the line's end). *>
fn sz literal_end(String s, sz k) @local
{
	char q = s[k++];
	while (k < s.len)
	{
		char c = s[k];
		if (q != '`' && c == '\\')
		{
			k += 2;
			continue;
		}
		if (q != '`' && c == '\n') return k;
		if (c == q)
		{
			if (q != '`' || k + 1 >= s.len || s[k + 1] != '`') return k + 1;
			k++;   // `` in a raw string
		}
		k++;
	}
	return k;
}

fn sz Src.len(&self) @inline => self.toks.len();
fn sz Src.end(&self, sz i) @inline => self.toks[i].start + self.toks[i].text.len;

<* The whitespace before token i (i == len: after the last token). *>
fn String Src.gap(&self, sz i)
{
	sz from = i == 0 ? 0 : self.end(i - 1);
	sz to = i < self.len() ? self.toks[i].start : self.text.len;
	return self.text[from:to - from];
}

<* Leading whitespace of a 1-based source line. *>
fn String Src.line_indent(&self, sz line)
{
	sz s = self.line_start[line - 1];
	sz e = s;
	while (e < self.text.len && (self.text[e] == ' ' || self.text[e] == '\t')) e++;
	return self.text[s:e - s];
}

<*
 Source indentation of the line token k is on. A line that begins inside a multi-line token
 (`*/ x`) belongs to the line where that token begins.
*>
fn String Src.indent_of(&self, sz k) => self.line_indent(self.toks[self.toks[k].row].line);

fn sz Src.prev_code(&self, sz i) @inline => i <= 0 || self.toks[i].cut ? NO : self.toks[i - 1].code ? i - 1 : self.toks[i - 1].prev;
fn sz Src.next_code(&self, sz i) @inline => self.toks[i].next;

fn TokenType Src.type_at(&self, sz i) @inline => i == NO || i >= self.len() ? TokenType.INVALID : self.toks[i].type;

<* Keep every gap of tokens from..to (inclusive), and the gap after the last token if to is the end. *>
fn void Src.keep_range(&self, sz from, sz to)
{
	for (sz k = from; k <= to && k < self.len(); k++) self.toks[k].keep = true;
}

<*
 Pair brackets with a stack. Damage stays local: the inside of an unclosed or
 mismatched bracket is kept as written. An opener that is never closed keeps everything up to the
 next top-level declaration (BREAK_WORDS), where the brackets start again from none.
*>
fn void Src.match_brackets(&self)
{
	List{sz} cuts;   // the tokens where an unclosed bracket ends
	cuts.tinit();
	List{sz} ranges;   // from, to of what is kept as written
	ranges.tinit();
	while (true)
	{
		sz b = self.pair_brackets(&cuts, &ranges);
		if (b == NO) break;
		cuts.push(b);
	}
	for (sz r = 0; r < ranges.len(); r += 2) self.keep_range(ranges[r], ranges[r + 1]);
	foreach (b : cuts) self.toks[b].cut = true;
	foreach (d : self.broken) self.unbalanced.push(d);
	for (sz i = 1; i < self.len(); i++) if (self.toks[i].cut) self.sever(i);
}

<* Token i starts a new statement: nothing before it is its previous code token, and the other way round. *>
fn void Src.sever(&self, sz i)
{
	for (sz k = i - 1; k >= 0; k--)
	{
		self.toks[k].next = (int)NO;
		if (self.toks[k].code) break;
	}
	for (sz k = i; k < self.len(); k++)
	{
		self.toks[k].prev = (int)NO;
		if (self.toks[k].code) break;
	}
}

fn Damage Src.damage(&self, sz tok, sz last) @inline => { .tok = tok, .last = last, .cause = "", .line = self.toks[last].line };

<* Is token i a line that starts at column 0 with a top-level declaration? *>
fn bool Src.is_break(&self, sz i)
{
	Tok* t = &self.toks[i];
	return t.start == self.line_start[t.line - 1] && is_break_token(t, true);
}

<*
 One pass of the pairing. Returns NO, or the token where one more unclosed bracket ends (the next
 pass then starts again from none there); `cuts` are the ones known.
*>
fn sz Src.pair_brackets(&self, List{sz}* cuts, List{sz}* ranges)
{
	self.unbalanced.clear();
	ranges.clear();
	foreach (&t : self.toks)
	{
		t.match = NO;
		t.dangling = false;
	}
	List{sz} stack;
	stack.tinit();
	List{sz} strays;   // stray closers whose enclosing span is only known at the end
	strays.tinit();
	sz next_cut = 0;
	for (sz i = 0; i < self.len(); i++)
	{
		Tok* t = &self.toks[i];
		bool cut = next_cut < cuts.len() && (*cuts)[next_cut] == i;
		if (cut) next_cut++;
		if (stack.len() && (cut || t.cut))
		{
			// (after a raw string or comment that is not closed the brackets before it are left alone: it is the damage)
			if (!cut)
			{
				// unless a top-level declaration starts between them
				for (sz j = stack[0] + 1; j < i; j++) if (self.is_break(j)) return j;
			}
			if (cut)
			{
				ranges.push(stack[0] + 1);
				ranges.push(i);
				while (stack.len()) self.unbalanced.push(self.damage(stack.pop()!!, i - 1));
			}
			foreach (o : stack) self.toks[o].dangling = !cut;
			stack.clear();
		}
		t.encl = stack.len() ? stack[^1] : NO;
		if (is_opener(t.type))
		{
			stack.push(i);
			continue;
		}
		if (!is_closer(t.type)) continue;
		// find the nearest opener of the right kind
		sz k = (sz)stack.len() - 1;
		while (k >= 0 && closer_of(self.toks[stack[k]].type) != t.type) k--;
		if (k < 0)
		{
			strays.push(i);
			continue;
		}
		// the openers left inside it are unclosed; their spans nest, so the outermost is kept
		if ((sz)stack.len() - 1 > k)
		{
			ranges.push(stack[k + 1] + 1);
			ranges.push(i);
		}
		while ((sz)stack.len() - 1 > k) self.unbalanced.push(self.damage(stack.pop()!!, i));
		sz o = stack.pop()!!;
		t.match = o;
		self.toks[o].match = i;
	}
	if (stack.len())
	{
		sz last_damaged = NO;
		foreach (j, &t : self.toks) if (t.damaged) last_damaged = j;
		bool damaged = last_damaged != NO && last_damaged > stack[0];
		for (sz j = stack[0] + 1; j <= (damaged ? last_damaged : self.len() - 1); j++) if (self.is_break(j)) return j;
		if (damaged)
		{
			foreach (o : stack) self.toks[o].dangling = true;
			stack.clear();   // the unterminated token at the end is the damage
		}
		else
		{
			ranges.push(stack[0] + 1);
			ranges.push(self.len() - 1);
			while (stack.len()) self.unbalanced.push(self.damage(stack.pop()!!, self.len() - 1));
		}
	}
	// a stray closer: the span around it is kept (at top level, its line)
	sz kept_to = NO;   // the end of the range kept for the stray closer before
	foreach (i : strays)
	{
		if (kept_to != NO && i <= kept_to)
		{
			// in the same span or on the same line as the one before: the same range
			self.unbalanced.push(self.damage(i, kept_to));
			continue;
		}
		sz e = self.toks[i].encl;
		sz from = e != NO ? e + 1 : i;
		sz to = e != NO && self.toks[e].match != NO ? self.toks[e].match : i;
		if (e == NO)
		{
			while (from > 0 && self.toks[from].nl == 0) from--;
			while (to + 1 < self.len() && self.toks[to + 1].nl == 0) to++;
		}
		else if (self.toks[e].match == NO)
		{
			to = self.len() - 1;
			foreach (d : self.unbalanced) if (d.tok == e) to = d.last;
		}
		self.unbalanced.push(self.damage(i, to));
		ranges.push(from);
		ranges.push(to);
		kept_to = to;
	}
	return NO;
}

<* First code token of the statement containing token i (stops at ; { } or an open bracket). *>
fn sz Src.stmt_start(&self, sz i)
{
	sz k = i;
	while (true)
	{
		sz p = self.prev_code(k);
		if (p == NO) return k;
		Tok* t = &self.toks[p];
		if (t.type == EOS || t.type == LBRACE || t.type == RBRACE || t.label) return k;
		if (is_opener(t.type)) return k;
		if (is_closer(t.type) && t.match != NO)
		{
			k = t.match;
			continue;
		}
		k = p;
	}
}

fn BraceKind Src.brace_kind(&self, sz i, BraceKind enclosing)
{
	sz p = self.prev_code(i);
	if (p == NO) return INIT;
	Tok* pt = &self.toks[p];
	switch (self.toks[self.stmt_start(i)].type)
	{
		case STRUCT: case UNION: case ENUM: case BITSTRUCT: case INTERFACE: case CONSTDEF: case CONSTSET:
			// header only: a '{' after '=' or '(' inside the header is something else
			if (pt.type != EQ && pt.type != COMMA && pt.type != LPAREN) return BODY;
		case FUNC: case MACRO:
			// the body of a function, whatever ends its header (`@inline`, `<Type>`, `@Attr`); not `=> expr`
			bool generic_args = (pt.type == TYPE_IDENT || pt.type == IDENT || pt.type == AT_TYPE_IDENT) && !self.after_params(i);   // `fn List{int} f()`
			if (self.toks[i].encl == NO && !generic_args && pt.type != EQ && pt.type != COMMA && !self.after_implies(i)) return BLOCK;
		default:
	}
	switch (pt.type)
	{
		case RPAREN:
			if (pt.match == NO) return INIT;
			TokenType bt = self.type_at(self.before_label(self.prev_code(pt.match)));
			switch (bt)
			{
				case IF: case WHILE: case FOR: case FOREACH: case FOREACH_R: case SWITCH: case DEFER:
				case IDENT: case AT_IDENT: case FUNC: case RBRACE: case RBRACKET: case HASH_IDENT:
				case CT_IDENT: case CONST_IDENT:
					return BLOCK;
				case STAR: case QUESTION:
					// `fn int*(int x) {`, `fn int?() {` return a pointer, an optional; `a * (Type){ … }` is a value
					sz k = self.prev_code(pt.match);
					while (self.type_at(k) == STAR || self.type_at(k) == QUESTION) k = self.prev_code(k);
					return is_type_token(self.type_at(k)) ? BLOCK : INIT;
				default:
					return is_type_token(bt) ? BLOCK : INIT;
			}
		case ELSE: case DO: case DEFER: case SWITCH: case AT_IDENT:
		case ASM: case TRY: case CATCH:
			return BLOCK;
		case RBRACE:
			// `List{int}{1, 2}`: what follows generic arguments is an initializer
			if (pt.match != NO && self.toks[pt.match].brace == GENERIC) return INIT;
			nextcase EOS;
		case EOS: case LBRACE:
			return enclosing == BLOCK || enclosing == NONE ? BLOCK : INIT;
		case TYPE_IDENT: case AT_TYPE_IDENT: case IDENT:
			if (pt.type == IDENT && pt.text == "excuse" && self.stmt_start(i) == p) return BODY;   // `excuse { A, B }`
			// `List{int}`, `foo{int}(x)`: an initializer never follows a name (since C3 0.7)
			return GENERIC;
		default:
			return pt.label ? BLOCK : INIT;
	}
}

<* `while LOOP: (` : the keyword before a label (k is the token before the '('). *>
fn sz Src.before_label(&self, sz k)
{
	if (self.type_at(k) != COLON) return k;
	sz l = self.prev_code(k);
	return self.type_at(l) == CONST_IDENT ? self.prev_code(l) : k;
}

<* Is there a parameter list in the statement before token i (`fn int f(int n) @Hot {`)? *>
fn bool Src.after_params(&self, sz i)
{
	for (sz k = self.stmt_start(i); k < i; k++)
	{
		if (self.toks[k].type == LPAREN && self.toks[k].encl == self.toks[i].encl) return true;
	}
	return false;
}

<* Is the '{' at o a bare block (after `;`, `{`, `}`, `$else` or `$endif`)? *>
fn bool Src.starts_statement(&self, sz o)
{
	TokenType p = self.type_at(self.prev_code(o));
	return p == INVALID || p == EOS || p == LBRACE || p == RBRACE || p == CT_ELSE || is_ct_end(p);
}

<* Is the '{' at o the body of a function or macro (`fn void f() {`, also after `@attr` or `<Type>`)? *>
fn bool Src.is_function_body(&self, sz o)
{
	if (self.toks[o].brace != BLOCK || self.toks[o].encl != NO) return false;
	TokenType start = self.toks[self.stmt_start(o)].type;
	return start == FUNC || start == MACRO;
}

<* Is the '{' at o the body of a lambda (`fn (int x) {`, `fn int() {`)? *>
fn bool Src.is_lambda_body(&self, sz o)
{
	sz p = self.prev_code(o);
	if (self.type_at(p) != RPAREN || self.toks[p].match == NO) return false;
	sz b = self.prev_code(self.toks[p].match);
	while (self.type_at(b) == STAR || self.type_at(b) == QUESTION) b = self.prev_code(b);   // `fn int?() {`
	if (self.type_at(b) == FUNC) return true;
	return b != NO && is_type_token(self.toks[b].type) && self.type_at(self.prev_code(b)) == FUNC;
}

<* Is there a top-level `=>` in the statement before token i (`macro m() => { … }`)? *>
fn bool Src.after_implies(&self, sz i)
{
	for (sz k = self.stmt_start(i); k < i; k++)
	{
		if (self.toks[k].type == IMPLIES && self.toks[k].encl == self.toks[i].encl) return true;
	}
	return false;
}

fn void Src.classify_braces(&self)
{
	for (sz i = 0; i < self.len(); i++)
	{
		Tok* t = &self.toks[i];
		if (t.type != LBRACE) continue;
		BraceKind enclosing = NONE;
		for (sz e = t.encl; e != NO; e = self.toks[e].encl)
		{
			if (self.toks[e].type == LBRACE)
			{
				enclosing = self.toks[e].brace;
				break;
			}
		}
		// labels are marked later; a block after a case label is found through BLOCK enclosing
		t.brace = self.brace_kind(i, enclosing);
		sz p = self.prev_code(i);
		if (t.brace == BLOCK && p != NO)
		{
			Tok* pt = &self.toks[p];
			// `switch (x) @jump {`, `switch LABEL: (x) {`
			while (true)
			{
				bool call = pt.type == RPAREN && pt.match != NO && self.type_at(self.prev_code(pt.match)) == AT_IDENT;
				sz a = pt.type == AT_IDENT ? p : call ? self.prev_code(pt.match) : NO;
				if (a == NO || self.prev_code(a) == NO) break;
				p = self.prev_code(a);
				pt = &self.toks[p];
			}
			t.is_switch = pt.type == SWITCH
				|| (pt.type == RPAREN && pt.match != NO && self.type_at(self.before_label(self.prev_code(pt.match))) == SWITCH);
			if (pt.type == ASM && t.match != NO) self.keep_range(i + 1, t.match);
		}
	}
}

fn bool is_ct_open(TokenType t) => t == CT_IF || t == CT_FOR || t == CT_FOREACH || t == CT_SWITCH;

fn TokenType ct_end_of(TokenType t)
{
	switch (t)
	{
		case CT_IF: return CT_ENDIF;
		case CT_FOR: return CT_ENDFOR;
		case CT_FOREACH: return CT_ENDFOREACH;
		default: return CT_ENDSWITCH;
	}
}

<* Pair $if/$for/$foreach/$switch with their $end keyword; $else points to its $if, $case to its $switch. *>
fn void Src.match_ct(&self)
{
	List{sz} stack;
	stack.tinit();
	for (sz i = 0; i < self.len(); i++)
	{
		Tok* t = &self.toks[i];
		if (t.cut) stack.clear();
		if (is_ct_open(t.type))
		{
			stack.push(i);
			continue;
		}
		switch (t.type)
		{
			case CT_ELSE:
				if (stack.len() && self.toks[stack[^1]].type == CT_IF) t.match = stack[^1];
			case CT_CASE: case CT_DEFAULT:
				if (stack.len() && self.toks[stack[^1]].type == CT_SWITCH) t.parent = stack[^1];
			case CT_ENDIF: case CT_ENDFOR: case CT_ENDFOREACH: case CT_ENDSWITCH:
				if (stack.len() && ct_end_of(self.toks[stack[^1]].type) == t.type)
				{
					sz o = stack.pop()!!;
					t.match = o;
					self.toks[o].match = i;
					self.toks[o].is_switch = t.type == CT_ENDSWITCH;
				}
			default:
		}
	}
}

<* The ':' that ends the label or header starting at token i, or NO. *>
fn sz Src.header_colon(&self, sz i, bool skip_first, bool semicolons = false)
{
	int ternary;
	bool skip = skip_first;
	for (sz k = i + 1; k < self.len(); k++)
	{
		Tok* t = &self.toks[k];
		if (t.cut) return NO;
		if (!t.code) continue;
		if (is_opener(t.type) && t.match != NO)
		{
			k = t.match;
			continue;
		}
		switch (t.type)
		{
			case EOS:
				if (!semicolons) return NO;
			case LBRACE: case RBRACE: return NO;
			case QUESTION: case CT_TERNARY: ternary++;
			case COLON:
				if (ternary > 0)
				{
					ternary--;
					break;
				}
				if (skip)
				{
					skip = false;
					break;
				}
				return k;
			default:
		}
	}
	return NO;
}

fn void Src.mark_labels(&self)
{
	for (sz i = 0; i < self.len(); i++)
	{
		Tok* t = &self.toks[i];
		sz colon = NO;
		switch (t.type)
		{
			case CASE: case DEFAULT:
				sz e = t.encl;
				if (e == NO || !self.toks[e].is_switch) break;
				t.parent = e;
				colon = self.header_colon(i, false);
			case CT_IF: case CT_SWITCH: case CT_CASE: case CT_DEFAULT:
				colon = self.header_colon(i, false);
			case CT_FOR:
				colon = self.header_colon(i, false, semicolons: true);
			case CT_FOREACH:
				colon = self.header_colon(i, true);
			case CT_ASSERT: case CT_ERROR:
				sz m = self.header_colon(i, false);
				if (m != NO) self.toks[m].message = true;
			default:
		}
		if (colon != NO) self.toks[colon].label = true;
	}
	// a '{' right after a label is a block
	for (sz i = 0; i < self.len(); i++)
	{
		Tok* t = &self.toks[i];
		if (t.type != LBRACE || t.brace != INIT) continue;
		sz p = self.prev_code(i);
		if (p != NO && self.toks[p].label) t.brace = BLOCK;
	}
}

<*
 Pair the '?' and ':' of each ternary like brackets, in one pass: a ':' that is not a label
 closes the nearest open '?' of its bracket. A ',' or ';' ends the open ones of its bracket, and
 so does a function or struct body (the '?' of `int? x;` or `fn int? f() {` belongs to a type);
 the '?' of a bracket that has been left ends there.
*>
fn void Src.mark_ternaries(&self)
{
	List{sz} open;   // '?' still waiting for their ':', the innermost last
	open.tinit();
	for (sz i = 0; i < self.len(); i++)
	{
		Tok* t = &self.toks[i];
		if (t.cut) open.clear();
		if (!t.code) continue;
		if (open.len())
		{
			// the brackets that were left take their '?' with them
			while (open.len() && !self.inside(t.encl, self.toks[open[^1]].encl)) (void)open.pop();
		}
		else if (t.type != QUESTION && t.type != CT_TERNARY)
		{
			continue;
		}
		switch (t.type)
		{
			case EOS: case COMMA: self.drop_open(&open, t.encl);
			case QUESTION: case CT_TERNARY: open.push(i);
			case COLON:
				if (t.label || !open.len() || self.toks[open[^1]].encl != t.encl) break;
				t.ternary = true;
				self.toks[open.pop()!!].ternary = true;
			case LBRACE:
				// (not the body of a lambda or the block of a call inside an expression: `a ? fn void() { … } : b`)
				if (t.brace == BODY || (t.brace == BLOCK && self.is_function_body(i))) self.drop_open(&open, t.encl);
			default:
		}
	}
}

<* Is bracket `inner` the bracket `outer` or inside it? (NO: the top level) *>
fn bool Src.inside(&self, sz inner, sz outer)
{
	for (sz b = inner; b != outer; b = self.toks[b].encl) if (b == NO) return false;
	return true;
}

<* The '?' still open in bracket `b` end here. *>
fn void Src.drop_open(&self, List{sz}* open, sz b)
{
	while (open.len() && self.toks[(*open)[^1]].encl == b) (void)open.pop();
}

fn bool is_directive(String comment, String word)
{
	String s = comment.trim();
	if (!s.starts_with("//")) return false;
	s = s[2..].trim();
	foreach (tool : (String[]){ "c3f ", "c3fmt " })
	{
		if (s.starts_with(tool)) return s[tool.len..].trim() == word;
	}
	return false;
}

<* `// c3f off` … `// c3f on` (or c3fmt): everything in between is kept as written. *>
fn void Src.mark_off_regions(&self)
{
	sz off = NO;
	for (sz i = 0; i < self.len(); i++)
	{
		Tok* t = &self.toks[i];
		if (t.type != LINE_COMMENT) continue;
		if (off == NO && is_directive(t.text, "off"))
		{
			off = i;
		}
		else if (off != NO && is_directive(t.text, "on"))
		{
			self.keep_range(off + 1, i);
			off = NO;
		}
	}
	if (off != NO) self.keep_range(off + 1, self.len() - 1);
}
