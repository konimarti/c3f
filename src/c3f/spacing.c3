module c3f;
import c3::lexer;

enum Space : char { KEEP, NONE, ONE }

<* One cell of the generated spacing table: how often the stdlib wrote no space / one space. *>
struct Rule
{
	char      level;      // 4: (p2, p1, next, bracket, before bracket)  3: (p2, p1, next)  2: (p1, next)
	TokenType p2, p1, nx, co, cb;
	uint      n0, n1;
}

<* Context of the gap before token i. *>
struct GapKey { TokenType p2, p1, nx, co, cb; }

fn GapKey Src.gap_key(&self, sz i)
{
	sz o = self.toks[i].encl;
	return {
		.p2 = i >= 2 ? self.toks[i - 2].type : INVALID,
		.p1 = self.toks[i - 1].type,
		.nx = self.toks[i].type,
		.co = o == NO ? TokenType.INVALID : self.toks[o].type,
		.cb = o == NO || o == 0 ? TokenType.INVALID : self.toks[o - 1].type,
	};
}

fn ulong pack(char level, TokenType p2, TokenType p1, TokenType nx, TokenType co, TokenType cb)
{
	return (ulong)level << 40 | (ulong)p2.ordinal << 32 | (ulong)p1.ordinal << 24
		| (ulong)nx.ordinal << 16 | (ulong)co.ordinal << 8 | (ulong)cb.ordinal;
}

<* The table cell of this context at a level: the fields the level does not look at are left out. *>
fn Rule GapKey.cell(&self, char level)
{
	return {
		.level = level,
		.p2 = level >= 3 ? self.p2 : TokenType.INVALID,
		.p1 = self.p1,
		.nx = self.nx,
		.co = level == 4 ? self.co : TokenType.INVALID,
		.cb = level == 4 ? self.cb : TokenType.INVALID,
	};
}

fn ulong GapKey.pack(&self, char level) => self.cell(level).pack();

fn GapKey Rule.key(&self) => {self.p2, self.p1, self.nx, self.co, self.cb};

fn ulong Rule.pack(&self) => pack(self.level, self.p2, self.p1, self.nx, self.co, self.cb);

// The table as open addressing over a fixed array: built once, never allocated.
const sz SLOTS = 8192;
Rule*[SLOTS] slots @local;
bool slots_ready @local;

fn sz slot_of(ulong key) @local => (sz)((key * 0x9E3779B97F4A7C15) >> 51);

<*
 The cell that decides a context: the most specific one. In strict mode, the most specific one
 that is consistent (an inconsistent context falls back to a broader one), or the broadest.
*>
fn Rule*? find_rule(GapKey* key, bool strict) @local
{
	$assert SPACING_RULES.len * 2 <= SLOTS : "spacing table too large: raise SLOTS";
	if (!slots_ready)
	{
		foreach (&r : SPACING_RULES)
		{
			sz k = slot_of(r.pack());
			while (slots[k]) k = (k + 1) & (SLOTS - 1);
			slots[k] = r;
		}
		slots_ready = true;
	}
	Rule* found;
	for (char level = 4; level >= 2; level--)
	{
		ulong want = key.pack(level);
		for (sz k = slot_of(want); slots[k]; k = (k + 1) & (SLOTS - 1))
		{
			if (slots[k].pack() != want) continue;
			if (!strict || slots[k].consistent()) return slots[k];
			found = slots[k];
			break;
		}
	}
	return found ?: NOT_FOUND~;
}

const float THRESHOLD = 0.99;

const uint MIN_COUNTER_EXAMPLES = 3;   // fewer than this against the majority is not a style

fn uint Rule.majority_count(&self) @inline => max(self.n0, self.n1);
fn bool Rule.consistent(&self) @inline => (float)self.majority_count() >= THRESHOLD * (float)(self.n0 + self.n1);

<* A cell that is neither consistent nor clearly inconsistent says nothing; its coarser cell decides. *>
fn bool Rule.weak(&self) => !self.consistent() && self.n0 + self.n1 - self.majority_count() < MIN_COUNTER_EXAMPLES;

<* The table's answer; strict mode takes the majority even where the stdlib is inconsistent. *>
fn Space Rule.decide(&self, bool strict)
{
	if (self.consistent() || (strict && self.n0 != self.n1)) return self.n1 > self.n0 ? Space.ONE : Space.NONE;
	return KEEP;   // inconsistent, or a tie even for strict
}

fn Space Src.table_space(&self, sz i, bool strict)
{
	GapKey key = self.gap_key(i);
	if (try r = find_rule(&key, strict)) return r.decide(strict);
	return KEEP;
}

fn bool is_operand_start(TokenType t)
{
	switch (t)
	{
		case IDENT: case CONST_IDENT: case INTEGER: case REAL: case STRING: case CHAR_LITERAL: case BYTES:
		case LPAREN: case AT_IDENT: case HASH_IDENT: case CT_IDENT: case NULL: case TRUE: case FALSE:
		case AMP: case STAR: case BANG: case BIT_NOT: case MINUS: case BUILTIN: case CT_VAARG:
		case CT_TYPEOF: case CT_REFLECT: case CT_EVAL: case PLUSPLUS: case MINUSMINUS:
			return true;
		default:
			return false;
	}
}

<* Is the ')' at r the end of a cast `(Type)`? (Cached: chains like `(A)(B)(C)x` stay linear.) *>
fn bool Src.is_cast_close(&self, sz r)
{
	if (!self.memo.len()) self.init_memo();
	if (self.memo[r] & 3) return (self.memo[r] & 3) == 2;
	bool v = self.cast_close_uncached(r);
	self.memo[r] |= v ? 2 : 1;
	return v;
}

fn void Src.init_memo(&self)
{
	self.memo.tinit();
	for (sz k = 0; k < self.len(); k++) self.memo.push(0);
}

fn bool Src.cast_close_uncached(&self, sz r)
{
	Tok* t = &self.toks[r];
	if (t.type != RPAREN || t.match == NO || r + 1 >= self.len()) return false;
	if (!is_operand_start(self.toks[r + 1].type)) return false;
	sz q = t.match;
	sz bi = self.prev_code(q);
	TokenType before = self.type_at(bi);
	if (before == RPAREN && self.toks[bi].match != NO && self.is_cast_close(bi)) before = INVALID;   // (A)(B)x
	switch (before)
	{
		case IDENT: case AT_IDENT: case CONST_IDENT: case RPAREN: case RBRACKET: case RBRACE: case IF:
		case WHILE: case FOR: case FOREACH: case FOREACH_R: case SWITCH: case HASH_IDENT: case CT_IDENT:
		case CATCH: case TRY: case FUNC: case MACRO: case CT_TYPEOF: case CT_REFLECT: case CT_DEFINED:
		case CT_EVAL: case CT_FEAT: case CT_TYPEFROM: case CT_STRINGIFY: case CT_ASSERT: case CT_ERROR:
		case CT_ECHO: case CT_EMBED: case CT_INCLUDE: case CT_EXEC: case CT_EXPAND: case CT_VAARG:
		case BUILTIN: case LENGTHOF: case ASSERT:
			return false;
		default:
			if (is_type_token(before)) return false;
	}
	if (q + 1 >= r) return false;
	TokenType first = self.toks[q + 1].type;
	if (!is_type_token(first) && !(first == IDENT && self.type_at(q + 2) == SCOPE)) return false;
	switch (self.toks[r - 1].type)
	{
		case STAR: case RBRACKET: case RVEC: case RBRACE: case QUESTION: break;
		default: if (!is_type_token(self.toks[r - 1].type)) return false;
	}
	for (sz k = q + 1; k < r; k++)
	{
		switch (self.toks[k].type)
		{
			case STAR: case LBRACKET: case RBRACKET: case INTEGER: case LVEC: case RVEC: case QUESTION:
			case SCOPE: case IDENT: case LBRACE: case RBRACE: case COMMA: case CONST_IDENT:
				break;
			default:
				if (!is_type_token(self.toks[k].type)) return false;
		}
	}
	return true;
}

<* Is the ':' at i the second half of a ternary `a ? b : c` (or `a ??? b : c`)? Cached like is_cast_close. *>
fn bool Src.is_ternary_colon(&self, sz i)
{
	if (!self.memo.len()) self.init_memo();
	if (self.memo[i] & 48) return (self.memo[i] & 48) == 32;
	bool v = self.ternary_colon_uncached(i);
	self.memo[i] |= v ? 32 : 16;
	return v;
}

fn bool Src.ternary_colon_uncached(&self, sz i)
{
	Tok* t = &self.toks[i];
	if (t.type != COLON || t.label) return false;
	sz e = t.encl;
	int pending;   // colons of ternaries nested inside this one, still waiting for their '?'
	for (sz k = i; k > 0;)
	{
		k--;
		if (k == e) return false;              // the opening bracket: no '?' before it
		Tok* p = &self.toks[k];
		if (p.encl != e || !p.code) continue;  // inside a nested bracket, or a comment
		switch (p.type)
		{
			case EOS: case COMMA: return false;
			case COLON:
				if (!p.label) pending++;
			case QUESTION: case CT_TERNARY:
				if (pending == 0) return true;
				pending--;
			default:
		}
	}
	return false;
}

<* Is the '?' at q the question of a ternary `c ? a : b` (not the '?' of an optional type `int[]?`)? *>
fn bool Src.is_ternary_question(&self, sz q)
{
	Tok* t = &self.toks[q];
	if (t.type != QUESTION) return false;
	sz e = t.encl;
	int pending;   // ternaries nested inside this one, still waiting for their ':'
	for (sz k = q + 1; k < self.len(); k++)
	{
		Tok* p = &self.toks[k];
		if (p.encl != e)
		{
			if (is_closer(p.type) && p.match == e) return false;   // the closing bracket: no ':'
			continue;                                              // inside a nested bracket
		}
		if (!p.code) continue;
		switch (p.type)
		{
			case EOS: case COMMA: return false;
			// a block or a body: the '?' was part of a type (`fn int? f() { … }`)
			case LBRACE: if (p.brace != INIT) return false;
			case QUESTION: pending++;
			case COLON:
				if (p.label) return false;
				if (pending == 0) return true;
				pending--;
			default:
		}
	}
	return false;
}

<* Is the ')' at r the end of the header of `if`, `while`, `for`, `foreach`, `foreach_r` or `switch`? *>
fn bool Src.is_header_close(&self, sz r)
{
	Tok* t = &self.toks[r];
	if (t.type != RPAREN || t.match == NO) return false;
	switch (self.type_at(self.prev_code(t.match)))
	{
		case IF: case WHILE: case FOR: case FOREACH: case FOREACH_R: case SWITCH: return true;
		default: return false;
	}
}

<* Is the ':' at i the one before the message of `$assert cond : "message"`? *>
fn bool Src.is_assert_colon(&self, sz i)
{
	Tok* t = &self.toks[i];
	if (t.type != COLON || t.label || t.encl != NO && self.toks[t.encl].type != LBRACE) return false;
	sz start = self.stmt_start(i);
	return self.toks[start].type == CT_ASSERT || self.toks[start].type == CT_ERROR;
}

<* Is the ':' at i the separator of a slice `s[a:b]`? *>
fn bool Src.is_slice_colon(&self, sz i)
{
	Tok* t = &self.toks[i];
	return t.type == COLON && !t.label && t.encl != NO && self.toks[t.encl].type == LBRACKET && !self.is_ternary_colon(i);
}

<* Is the '*' at s part of a pointer type (`Foo* p`, `(int*)x`)? (Cached, like is_cast_close.) *>
fn bool Src.is_type_star(&self, sz s)
{
	if (s >= self.len()) return false;
	if (!self.memo.len()) self.init_memo();
	if (self.memo[s] & 12) return (self.memo[s] & 12) == 8;
	bool v = self.type_star_uncached(s);
	self.memo[s] |= v ? 8 : 4;
	return v;
}

fn bool Src.type_star_uncached(&self, sz s)
{
	if (s == 0 || s + 1 >= self.len() || self.toks[s].type != STAR) return false;
	Tok* p = &self.toks[s - 1];
	bool typed;
	switch (p.type)
	{
		case STAR: typed = self.is_type_star(s - 1);
		case RBRACKET: case RVEC: case RBRACE:
			typed = p.match != NO && p.match > 0 && is_type_token(self.toks[p.match - 1].type);
		default: typed = is_type_token(p.type);
	}
	if (!typed) return false;
	switch (self.toks[s + 1].type)
	{
		case IDENT: case CT_IDENT: case HASH_IDENT: case RPAREN: case COMMA: case STAR: case EOS: case RBRACKET:
		case LBRACKET: case CT_TYPE_IDENT: case TYPE_IDENT:   // `Foo* Bar.method()`
			return true;
		default:
			return false;
	}
}

fn bool is_operator_text(String t)
{
	if (t.len == 0) return false;
	foreach (c : t) if (!is_op_char(c)) return false;
	return true;
}

fn bool Src.same_line(&self, sz i) @inline => i > 0 && i < self.len() && self.toks[i].nl == 0;

<*
 Space for the same-line gap before token i, before the guards. Both sides of an operator
 follow the source if either side does, so `a*b` and `a *b` never become lopsided.
*>
fn Space Src.space_rule(&self, sz i, Config* cfg)
{
	if (self.is_unary(i - 1)) return NONE;
	Space rule = self.gap_rule(i, cfg);
	// the inside of a one-line `{ … }` is padded alike on both ends
	sz open = self.toks[i - 1].type == LBRACE ? i - 1 : self.toks[i].type == RBRACE ? self.toks[i].match : NO;
	// (both inner gaps on the line: a `{ … }` that was wrapped keeps the padding it had on one line)
	if (open != NO && self.toks[open].brace != GENERIC && self.toks[open].match > open + 1
		&& self.toks[open + 1].nl == 0 && self.toks[self.toks[open].match].nl == 0)
	{
		sz close = self.toks[open].match;
		Space a = self.gap_rule(open + 1, cfg);
		Space b = self.gap_rule(close, cfg);
		// the sides disagree, or one follows the source: a symmetric source stays, a lopsided one gets spaces
		if (a == KEEP || b == KEEP || a != b) return (self.gap(open + 1).len > 0) == (self.gap(close).len > 0) ? Space.KEEP : Space.ONE;
	}
	if (rule == KEEP) return KEEP;
	if (is_operator_text(self.toks[i].text) && self.same_line(i + 1))
	{
		Space after = self.gap_rule(i + 1, cfg);
		if (after == KEEP) return KEEP;
		if (after != rule && self.is_binary(i)) return self.symmetric(i);
	}
	if (is_operator_text(self.toks[i - 1].text) && self.same_line(i - 1))
	{
		Space before = self.gap_rule(i - 1, cfg);
		if (before == KEEP) return KEEP;
		if (before != rule && self.is_binary(i - 1)) return self.symmetric(i - 1);
	}
	return rule;
}

<* The table disagrees about the two sides of binary operator o: a symmetric source stays, a lopsided one gets spaces. *>
fn Space Src.symmetric(&self, sz o)
{
	bool before = self.gap(o).len > 0;
	bool after = self.gap(o + 1).len > 0;
	return before == after ? Space.KEEP : Space.ONE;
}

<* Is token o a prefix operator (`-x`, `*p`, `&v`, `!b`, `~m`) right before its operand? *>
fn bool Src.is_unary(&self, sz o)
{
	if (o >= self.len() - 1) return false;
	switch (self.toks[o].type)
	{
		case MINUS: case STAR: case AMP: case BANG: case BIT_NOT: case PLUS:
			break;
		default:
			return false;
	}
	if (!self.same_line(o + 1) || !is_operand_start(self.toks[o + 1].type)) return false;
	// what comes before, comments skipped
	sz pi = self.prev_code(o);
	if (pi == NO) return true;
	Tok* p = &self.toks[pi];
	switch (p.type)
	{
		case LPAREN: case LBRACKET: case LBRACE: case LVEC: case COMMA: case EOS: case COLON: case IMPLIES:
		case RETURN: case CASE: case ASSERT:
		case CT_ELSE: case CT_ENDIF: case CT_ENDFOR: case CT_ENDFOREACH: case CT_ENDSWITCH:   // `$endif *p = 1;`
			return true;
		case RBRACE:
			// a statement after a block: `} *p = 1;`
			return p.match != NO && (self.toks[p.match].brace == BLOCK || self.toks[p.match].brace == BODY);
		case RPAREN:
			// after a cast, or at the start of the statement of `if (…)`, `foreach (…)`, …
			return self.is_cast_close(pi) || self.is_header_close(pi);
		case BANG: case BANGBANG: case BIT_NOT: case PLUSPLUS: case MINUSMINUS:
			// postfix after an operand (`foo()! + 1`, `i++ - 1`): then o is binary
			sz before = self.prev_code(pi);
			return before == NO || !is_operand_end(self.toks[before].type);
		case STAR:
			return !self.is_type_star(pi) && self.is_unary(pi);
		default:
			return is_operator_text(p.text);
	}
}

fn bool is_operand_end(TokenType t)
{
	switch (t)
	{
		case IDENT: case CONST_IDENT: case INTEGER: case REAL: case STRING: case CHAR_LITERAL: case BYTES:
		case RPAREN: case RBRACKET: case TRUE: case FALSE: case NULL: case CT_IDENT: case HASH_IDENT:
			return true;
		default:
			return false;
	}
}

fn bool is_binary_op(TokenType t)
{
	switch (t)
	{
		case STAR: case DIV: case MOD: case PLUS: case MINUS: case AMP: case BIT_OR: case BIT_XOR: case SHL_OP:
		case SHR_OP: case EQEQ: case NOT_EQUAL: case LESS_EQ: case GREATER_EQ:
		case AND: case OR: case QUESTQUEST: case ELVIS: case EQ: case PLUS_ASSIGN: case MINUS_ASSIGN: case DOTDOT:
		case MULT_ASSIGN: case DIV_ASSIGN: case MOD_ASSIGN: case SHL_ASSIGN: case SHR_ASSIGN:
		case BIT_AND_ASSIGN: case BIT_OR_ASSIGN: case BIT_XOR_ASSIGN: case CT_AND_OP: case CT_OR_OP: case CT_CONCAT_OP:
			return true;
		default:
			return false;
	}
}

<* Is token o an infix operator between two operands (not a cast, not a pointer type)? *>
fn bool Src.is_binary(&self, sz o)
{
	if (o == 0 || o + 1 >= self.len() || !is_binary_op(self.toks[o].type)) return false;
	TokenType p = self.toks[o - 1].type;
	if (!is_operand_end(p) || !is_operand_start(self.toks[o + 1].type)) return false;
	if (p == RPAREN && self.is_cast_close(o - 1)) return false;
	// `if (x) *p = 1;`: what follows a control header starts a statement
	if (p == RPAREN && self.is_header_close(o - 1)) return false;
	return !self.is_type_star(o);
}

fn Space Src.gap_rule(&self, sz i, Config* cfg)
{
	Tok* prev = &self.toks[i - 1];
	Tok* next = &self.toks[i];
	// `a ? b : c`: the ':' has a space on both sides (it is not a label, slice or named argument)
	if ((next.type == COLON && self.is_ternary_colon(i)) || (prev.type == COLON && self.is_ternary_colon(i - 1))) return ONE;
	if ((next.type == QUESTION && self.is_ternary_question(i)) || (prev.type == QUESTION && self.is_ternary_question(i - 1))) return ONE;
	// strict: generic arguments are tight, `List{Table[3]}` (the stdlib also writes `HashMap { K, V }`)
	if (cfg.spacing == STRICT)
	{
		if (prev.type == LBRACE && prev.brace == GENERIC && next.type != RBRACE) return NONE;
		if (next.type == RBRACE && next.match != NO && self.toks[next.match].brace == GENERIC && prev.type != LBRACE) return NONE;
	}
	// strict: a one-line block or body is spaced inside, as the stdlib writes `{ return x; }`
	if (cfg.spacing == STRICT)
	{
		if (prev.type == LBRACE && (prev.brace == BLOCK || prev.brace == BODY) && next.type != RBRACE) return ONE;
		if (next.type == RBRACE && next.match != NO && prev.type != LBRACE)
		{
			BraceKind k = self.toks[next.match].brace;
			if (k == BLOCK || k == BODY) return ONE;
		}
	}
	// the ':' of a label or compile-time header is tight: `case X:`, `$if cond:`
	if (next.type == COLON && next.label) return NONE;
	// strict: the parameter list of a function type is tight, `fn Type(...)` like `fn void(...)`
	if (cfg.spacing == STRICT && next.type == LPAREN && i >= 2 && self.toks[i - 2].type == FUNC && is_type_token(prev.type)) return NONE;
	// `$assert cond : "message"`
	if ((next.type == COLON && self.is_assert_colon(i)) || (prev.type == COLON && self.is_assert_colon(i - 1))) return ONE;
	// `if (x) y;`: the statement after a control header is spaced off
	if (prev.type == RPAREN && self.is_header_close(i - 1) && next.type != EOS && next.type != LBRACE) return ONE;
	// `s[a:b]`: in strict mode a slice's ':' sits tight (the stdlib writes both `[a:b]` and `[a : b]`)
	if (cfg.spacing == STRICT && ((next.type == COLON && self.is_slice_colon(i)) || (prev.type == COLON && self.is_slice_colon(i - 1)))) return NONE;
	if (prev.type == RPAREN && self.is_cast_close(i - 1)) return cfg.space_after_cast ? Space.ONE : Space.NONE;
	if (cfg.pointer_style == KEEP)
	{
		if ((next.type == STAR && self.is_type_star(i)) || (prev.type == STAR && self.is_type_star(i - 1))) return KEEP;
	}
	else
	{
		bool ident_after = next.type == IDENT || next.type == CT_IDENT || next.type == HASH_IDENT || next.type == TYPE_IDENT;
		if (next.type == STAR && self.is_type_star(i))
		{
			if (prev.type == STAR) return NONE;
			return cfg.pointer_style == TYPE ? Space.NONE : Space.ONE;
		}
		if (prev.type == STAR && self.is_type_star(i - 1) && next.type != STAR)
		{
			return cfg.pointer_style == TYPE && ident_after ? Space.ONE : Space.NONE;
		}
	}
	if (cfg.bracket_padding != KEEP)
	{
		Space pad = cfg.bracket_padding == SPACE ? Space.ONE : Space.NONE;
		if (prev.type == LBRACKET && next.type != RBRACKET) return pad;
		if (next.type == RBRACKET && prev.type != LBRACKET) return pad;
		// the gap itself is on a line (the caller only asks for those), whatever the rest of the braces does
		if (prev.type == LBRACE && prev.brace == INIT && prev.match != i) return pad;
		if (next.type == RBRACE && next.match != NO && self.toks[next.match].brace == INIT && prev.type != LBRACE) return pad;
	}
	return self.table_space(i, cfg.spacing == STRICT);
}

<* Removing the space between a and b keeps them two tokens of the same kind. *>
fn bool glue_safe(String a, String b, TokenType ta, TokenType tb)
{
	@pool()
	{
		String joined = a.tconcat(b);
		Lexer lx;
		lx.init(joined);
		Token? t1 = lx.next();
		Token? t2 = lx.next();
		if (catch t1) return false;
		if (catch t2) return false;
		if (t1.type != ta || t2.type != tb || t1.text != a || t2.text != b) return false;
		if (try t3 = lx.next()) return t3.type == EOF;
		return true;
	};
}

fn bool is_op_char(char c) => @ok("+-*/%&|^~!<>=?:.".index_of_char(c));

<* Could the text of a and b, written together, be read as one future token? *>
fn bool may_join(String a, String b)
{
	if (a.len == 0 || b.len == 0) return false;
	char x = a[^1];
	char y = b[0];
	return (is_op_char(x) && is_op_char(y)) || (x == '[' && y == '<') || (x == '>' && y == ']');
}
