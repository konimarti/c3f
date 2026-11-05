module c3f;
import c3::lexer, std::collections::list;

// Line wrapping: `c3f_line_breaks = long | fit`.
//
// A statement (a head line and its continuation lines) is a sequence of elements: runs of
// tokens that never break inside, and bracket spans. Between two elements there may be a
// wrap point (after ',', after '=', before a binary operator) with a cost multiplier. A span
// is laid out one of three ways (rfmt's choice blocks): inline (items fill the line, wrapping
// at its commas), hanging (a break after the opener), or stacked (one item per line).
//
// The cost of a layout is rfmt's: per character past the soft margin, per character past the
// hard margin, and per line break. Because columns are integers, the optimal cost of each
// piece as a function of its start column is kept as a table over the columns 0..W, which is
// exactly rfmt's piecewise-linear solution sampled at every column.

enum ElemKind : char @local { RUN, SPAN }

struct Elem @local
{
	ElemKind kind;
	sz       first;         // first token
	sz       width;         // RUN: rendered width
	sz       seq;           // SPAN: its inner sequence
}

enum Point : char @local { NONE, COMMA, ASSIGN, OPERATOR, OPEN, CLOSE }

<* A sequence of elements with wrap points between them. *>
struct Seq @local
{
	List{sz}    elems;
	List{Point} points;     // points[j]: before elems[j] (points[0] unused)
	List{float} mults;
	sz          depth;      // continuation level of lines broken inside it
	bool        magic;      // a trailing comma: one item per line
	bool        frozen;     // inside a one-line block: never breaks
	sz          tail;       // width of the text that has to follow it on its last line
}

enum Layout : char @local { INLINE, HANG, STACK }

<* Optimal cost of laying out a piece from column c (0..W), and where it ends. *>
struct Table @local
{
	float[] cost;
	sz[]    end;
	char[]  pick;     // sequence step: bit 0 = break before the next element, bits 1-2 = this span's layout
}

struct Wrap @local
{
	Fmt*        f;
	List{Elem}  elems;
	List{Seq}   seqs;
	List{sz}     join_w; // its display width
	List{bool}   stmts;  // per token: a '{' with statements inside
	sz          first, last;
	Indent      base;
	sz          w;       // columns kept in a table
	float       c0, c1, cb;
	sz          m0, m1;
	// solutions, filled on demand
	List{bool}     span_done;
	List{Table[3]} span_layouts;  // per span: its solution under each layout
	List{List{Table}} steps;      // per (sequence, layout): the solver's steps, for reading back
	sz             top;           // the statement's own sequence
}

fn sz rank(TokenType t) @local
{
	switch (t)
	{
		case QUESTION: case ELVIS: return 2;
		case OR: case CT_OR_OP: return 3;
		case AND: case CT_AND_OP: return 4;
		case EQEQ: case NOT_EQUAL: case LESS: case GREATER: case LESS_EQ: case GREATER_EQ: return 5;
		case PLUS: case MINUS: return 6;
		case QUESTQUEST: return 7;
		case AMP: case BIT_OR: case BIT_XOR: return 8;
		case SHL_OP: case SHR_OP: return 9;
		default: return 10;
	}
}

fn bool is_assign(TokenType t) @local
{
	switch (t)
	{
		case EQ: case PLUS_ASSIGN: case MINUS_ASSIGN: case MULT_ASSIGN: case DIV_ASSIGN: case MOD_ASSIGN:
		case SHL_ASSIGN: case SHR_ASSIGN: case BIT_AND_ASSIGN: case BIT_OR_ASSIGN: case BIT_XOR_ASSIGN:
		case CT_CONCAT_ASSIGN:
			return true;
		default:
			return false;
	}
}

// ---- building ------------------------------------------------------------------------------

<* Elements of tokens a..b (inclusive) as a new sequence; returns its index. *>
fn sz Wrap.build(&self, sz a, sz b, sz depth)
{
	Src* s = self.f.src;
	sz index = self.seqs.len();
	self.seqs.push({.depth = depth});
	self.seqs[index].elems.tinit();
	self.seqs[index].points.tinit();
	self.seqs[index].mults.tinit();
	sz k = a;
	while (k <= b)
	{
		Tok* t = &s.toks[k];
		if (self.opens_span(k, b))
		{
			sz inner = self.build_span(k, depth + 1);
			self.elems.push({.kind = SPAN, .first = k, .seq = inner});
			k = t.match + 1;
		}
		else
		{
			// a run up to the next wrap point or bracket
			sz r = k;
			sz width = text_width(t.text, 0, self.f.cfg.tab_width);
			while (r + 1 <= b && self.point_before(r + 1) == NONE && !self.opens_span(r + 1, b))
			{
				r++;
				width += self.join_w[r - self.first] + text_width(s.toks[r].text, 0, self.f.cfg.tab_width);
			}
			self.elems.push({.kind = RUN, .first = k, .width = width});
			k = r + 1;
		}
		sz e = self.elems.len() - 1;   // the element just added (a span's inside was added before it)
		Point p = self.seqs[index].elems.len() ? self.point_before(self.elems[e].first) : Point.NONE;
		self.seqs[index].elems.push(e);
		self.seqs[index].points.push(p);
		self.seqs[index].mults.push(self.mult(p, self.elems[e].first, depth));
	}
	return index;
}

<*
 What follows a span on its line until the sequence around it can break: a span chooses its
 breaks for itself, so it has to see that text (`f(a, b)) return x;` breaks inside the
 arguments when the `return` does not fit).
*>
fn void Wrap.set_tails(&self, sz seq, sz tail)
{
	self.seqs[seq].tail = tail;
	sz n = self.seqs[seq].elems.len();
	for (sz j = 0; j < n; j++)
	{
		Elem* el = &self.elems[self.seqs[seq].elems[j]];
		if (el.kind != SPAN) continue;
		sz after;
		bool to_end = true;
		for (sz k = j + 1; k < n; k++)
		{
			Seq* q = &self.seqs[seq];
			Point p = q.points[k];
			if (!q.frozen && p != NONE && (p != CLOSE || q.magic))
			{
				to_end = false;
				break;
			}
			Elem* next = &self.elems[q.elems[k]];
			after += self.join_w[next.first - self.first];
			if (next.kind == RUN)
			{
				after += next.width;
				continue;
			}
			// a span right after (`f(a)[i]`): its opener is certain, the rest may break
			after += text_width(self.f.src.toks[next.first].text, 0, self.f.cfg.tab_width);
			if (!self.seqs[next.seq].frozen)
			{
				to_end = false;
				break;
			}
			after += self.span_width(next.first) - text_width(self.f.src.toks[next.first].text, 0, self.f.cfg.tab_width);
		}
		self.set_tails(el.seq, to_end ? after + tail : after);
	}
}

<* Width of the span opened at token `open` written on one line. *>
fn sz Wrap.span_width(&self, sz open)
{
	Src* s = self.f.src;
	sz w = text_width(s.toks[open].text, 0, self.f.cfg.tab_width);
	for (sz k = open + 1; k <= s.toks[open].match; k++) w += self.join_w[k - self.first] + text_width(s.toks[k].text, 0, self.f.cfg.tab_width);
	return w;
}

fn bool Wrap.opens_span(&self, sz k, sz b)
{
	Tok* t = &self.f.src.toks[k];
	return (t.type == LPAREN || t.type == LBRACKET || (t.type == LBRACE && t.brace == INIT))
		&& t.match != NO && t.match <= b && !self.has_statements(k);
}

<* Is token k inside a one-line block `{ a; b; }`? Breaking there would make it a block of several lines. *>
fn bool Wrap.blocked(&self, sz k)
{
	Src* s = self.f.src;
	for (sz e = s.toks[k].encl; e != NO && e >= self.first; e = s.toks[e].encl)
	{
		Tok* o = &s.toks[e];
		if (self.has_statements(e)) return true;
		// generic arguments, block bodies, index brackets and attribute arguments stay on one line
		if (o.type == LBRACE && o.brace != INIT) return true;
		if (o.type == LBRACKET || o.type == LVEC) return true;
		if (o.type == LPAREN && e > 0 && is_attribute(s, e - 1)) return true;
	}
	return false;
}

<* Is token k the name of an attribute (`@cname("x")` after a declaration), not a macro call (`return @m(x)`)? *>
fn bool is_attribute(Src* s, sz k) @local
{
	if (s.toks[k].type != AT_IDENT && s.toks[k].type != AT_TYPE_IDENT) return false;
	switch (s.type_at(s.prev_code(k)))
	{
		case IDENT: case TYPE_IDENT: case CONST_IDENT: case RPAREN: case RBRACKET: case AT_IDENT: case AT_TYPE_IDENT:
			return true;
		default:
			return false;
	}
}

<* A break after this comma starts a new element of the list the statement is in (enum values, table rows). *>
fn bool Wrap.list_comma(&self, sz k)
{
	Src* s = self.f.src;
	sz e = s.toks[k].encl;
	if (s.toks[k - 1].type != COMMA || e == NO || e >= self.first) return false;
	return s.toks[e].type == LBRACE && s.toks[e].brace != BLOCK;
}

<* A `{ … }` with statements inside (a one-line block) never breaks. *>
fn bool Wrap.has_statements(&self, sz open) @inline => open >= self.first && self.stmts[open - self.first];

<* Mark every `{` of the statement that has a ';' inside (once, instead of scanning per question). *>
fn void Wrap.find_statements(&self)
{
	Src* s = self.f.src;
	self.stmts.tinit();
	for (sz k = self.first; k <= self.last; k++) self.stmts.push(false);
	for (sz k = self.first; k <= self.last; k++)
	{
		if (s.toks[k].type != EOS) continue;
		for (sz e = s.toks[k].encl; e != NO && e >= self.first; e = s.toks[e].encl)
		{
			if (s.toks[e].type != LBRACE) continue;
			if (self.stmts[e - self.first]) break;
			self.stmts[e - self.first] = true;
		}
	}
}

<* The inside of a span, with its opener and closer as runs of their own. *>
fn sz Wrap.build_span(&self, sz open, sz depth)
{
	Src* s = self.f.src;
	sz close = s.toks[open].match;
	sz index = self.seqs.len();
	self.seqs.push({.depth = depth, .magic = self.f.cfg.magic_comma && s.toks[close - 1].type == COMMA && close > open + 1,
		.frozen = self.blocked(open + 1)});
	Seq* q = &self.seqs[index];
	q.elems.tinit();
	q.points.tinit();
	q.mults.tinit();
	self.push_run(index, open, NONE, depth);
	if (close > open + 1)
	{
		sz inner = self.build(open + 1, close - 1, depth);
		Seq* in = &self.seqs[inner];
		foreach (j, e : in.elems)
		{
			Point p = j == 0 ? Point.OPEN : in.points[j];
			self.seqs[index].elems.push(e);
			self.seqs[index].points.push(p);
			self.seqs[index].mults.push(j == 0 ? self.mult(OPEN, open + 1, depth) : in.mults[j]);
		}
	}
	self.push_run(index, close, close > open + 1 ? Point.CLOSE : Point.NONE, depth);
	return index;
}

fn void Wrap.push_run(&self, sz seq, sz tok, Point p, sz depth)
{
	sz e = self.elems.len();
	self.elems.push({.kind = RUN, .first = tok, .width = text_width(self.f.src.toks[tok].text, 0, self.f.cfg.tab_width)});
	self.seqs[seq].elems.push(e);
	self.seqs[seq].points.push(p);
	self.seqs[seq].mults.push(self.mult(p, tok, depth));
}

<* Can the line break before token k? *>
fn Point Wrap.point_before(&self, sz k)
{
	Src* s = self.f.src;
	if (k <= self.first || k > self.last) return NONE;
	if (self.blocked(k)) return NONE;
	TokenType prev = s.toks[k - 1].type;
	if (prev == COMMA) return COMMA;
	// `=` inside parentheses (`for (int i = 0; …)`, named arguments) is no place to break
	if (is_assign(prev))
	{
		sz e = s.toks[k].encl;
		return e != NO && s.toks[e].type == LPAREN ? Point.NONE : Point.ASSIGN;
	}
	if (s.is_binary(k) && !is_assign(s.toks[k].type)) return OPERATOR;
	return NONE;
}

// Break cost multipliers (times c3f_wrap_cost_break): per level of nesting, after an opener or
// before a closer, after '=', before an operator (plus per precedence rank: `||` is cheaper than `*`).
const float DEPTH_COST = 0.5f;
const float BRACKET_COST = 1.5f;
const float ASSIGN_COST = 1.5f;
const float OPERATOR_COST = 0.5f;
const float PRECEDENCE_COST = 0.1f;
// columns past the line limit that the cost tables cover before extrapolating
const sz SLACK_COLUMNS = 40;

<* Cost multiplier of a break: outer breaks and low-precedence operators are cheaper. *>
fn float Wrap.mult(&self, Point p, sz k, sz depth)
{
	float d = 1 + DEPTH_COST * (float)depth;
	switch (p)
	{
		case NONE: return 0;
		case COMMA: return d;
		case OPEN: case CLOSE: return BRACKET_COST * d;
		case ASSIGN: return ASSIGN_COST * d;
		case OPERATOR: return (OPERATOR_COST + PRECEDENCE_COST * (float)rank(self.f.src.toks[k].type)) * d;
	}
}

// ---- solving -------------------------------------------------------------------------------

<* Column of a line broken inside a sequence of this depth (a closer goes one level out). *>
fn sz Wrap.target(&self, Seq* q, sz j)
{
	sz d = q.points[j] == CLOSE ? q.depth - 1 : max(q.depth, 1);
	if (q.depth == 0 && self.list_comma(self.elems[q.elems[j]].first)) d = 0;
	return self.f.indent_width(self.base.deeper(d));
}

fn float Wrap.text_cost(&self, sz c, sz width)
{
	sz end = c + width;
	float cost;
	if (end > self.m0) cost += self.c0 * (float)(end - max(c, self.m0));
	if (end > self.m1) cost += self.c1 * (float)(end - max(c, self.m1));
	return cost;
}

<* Value of a table at any column (past W the line only gets longer). *>
fn float Wrap.at(&self, Table* t, sz c, sz* end)
{
	if (c <= self.w)
	{
		*end = t.end[c];
		return t.cost[c];
	}
	*end = t.end[self.w] + (c - self.w);
	return t.cost[self.w] + (self.c0 + self.c1) * (float)(c - self.w);
}

fn Table Wrap.new_table(&self)
{
	Table t = {mem::talloc_array(float, self.w + 1), mem::talloc_array(sz, self.w + 1), mem::talloc_array(char, self.w + 1)};
	t.pick[..] = 0;
	return t;
}

<* Solutions of span element e under each layout (INLINE, HANG, STACK), as tables over the start column. *>
fn Table[3]* Wrap.layouts(&self, sz e)
{
	sz seq = self.elems[e].seq;
	if (!self.span_done[seq])
	{
		Table[3] tables;
		for (int l = 0; l < 3; l++) tables[l] = self.solve(seq, (Layout)l);
		self.span_layouts[seq] = tables;
		self.span_done[seq] = true;
	}
	return &self.span_layouts[seq];
}

<* Is the point before element j of seq allowed / forced under a layout? *>
fn bool Wrap.allowed(&self, Seq* q, sz j, Layout l)
{
	if (q.frozen) return false;
	switch (q.points[j])
	{
		case NONE: return false;
		case OPEN: return l != INLINE;
		case CLOSE: return q.magic && l == STACK;
		default: return true;
	}
}

fn bool Wrap.forced(&self, Seq* q, sz j, Layout l)
{
	if (q.frozen) return false;
	switch (q.points[j])
	{
		case OPEN: return l != INLINE;
		case COMMA: return l == STACK;
		case CLOSE: return q.magic && l == STACK;
		default: return false;
	}
}

<* Best way to go on after element i ends at column `end`: stay on the line, or break before element i + 1. *>
fn float Wrap.continue_after(&self, Seq* q, List{Table}* steps, sz i, Layout l, sz end, sz* rest_end, char* brk)
{
	float best = float::inf;
	*brk = 0;
	if (!self.forced(q, i + 1, l))
	{
		sz gap = self.join_w[self.elems[q.elems[i + 1]].first - self.first];
		best = self.at(&(*steps)[i + 1], end + gap, rest_end);
	}
	if (self.allowed(q, i + 1, l))
	{
		sz e2;
		float cost = self.cb * q.mults[i + 1] + self.at(&(*steps)[i + 1], self.target(q, i + 1), &e2);
		if (cost < best)
		{
			best = cost;
			*rest_end = e2;
			*brk = 1;
		}
	}
	return best;
}

<*
 Solve a sequence for every start column, right to left: steps[j] is the best way to lay
 out elements j.. starting at a column; it either continues on the line or breaks before j+1.
*>
fn Table Wrap.solve(&self, sz seq, Layout l)
{
	Seq* q = &self.seqs[seq];
	sz n = q.elems.len();
	List{Table} steps;
	steps.tinit();
	for (sz j = 0; j < n; j++) steps.push(self.new_table());
	for (sz j = n; j > 0; j--)
	{
		sz i = j - 1;
		Table* t = &steps[i];
		Elem* el = &self.elems[q.elems[i]];
		// a span's layout is chosen together with what follows it on the line (rfmt's
		// choice blocks see the rest of the line): every layout is tried with every continuation
		int first_layout = el.kind == SPAN && self.seqs[el.seq].magic ? 2 : 0;
		int last_layout = el.kind == SPAN ? 2 : 0;
		Table[3]* lay = el.kind == SPAN ? self.layouts(q.elems[i]) : null;
		for (sz c = 0; c <= self.w; c++)
		{
			t.cost[c] = float::inf;
			for (int k = first_layout; k <= last_layout; k++)
			{
				sz end;
				float cost;
				if (lay)
				{
					cost = self.at(&(*lay)[k], c, &end);
				}
				else
				{
					end = c + el.width;
					cost = self.text_cost(c, el.width);
				}
				sz rest_end = end;
				char brk;
				if (i < n - 1) cost += self.continue_after(q, &steps, i, l, end, &rest_end, &brk);
				// the text glued to the end of the span counts in the choice (the parent pays for it again)
				if (i == n - 1 && q.tail) cost += self.text_cost(end, q.tail);
				if (cost < t.cost[c])
				{
					t.cost[c] = cost;
					t.end[c] = rest_end;
					t.pick[c] = brk | (char)(k << 1);
				}
			}
		}
	}
	// keep the steps for reading the layout back
	self.steps_of(seq, l).clear();
	foreach (st : steps) self.steps_of(seq, l).push(st);
	if (!q.tail) return steps[0];
	// the parent lays the tail out itself: hand it the cost without it
	Table out = self.new_table();
	for (sz c = 0; c <= self.w; c++)
	{
		out.end[c] = steps[0].end[c];
		out.pick[c] = steps[0].pick[c];
		out.cost[c] = steps[0].cost[c] - self.text_cost(steps[0].end[c], q.tail);
	}
	return out;
}

fn List{Table}* Wrap.steps_of(&self, sz seq, Layout l) => &self.steps[seq * 3 + l.ordinal];

<* Read the chosen layout of sequence seq (layout l) from column c into `breaks`. *>
fn void Wrap.read(&self, sz seq, Layout l, sz c, List{bool}* breaks)
{
	Seq* q = &self.seqs[seq];
	List{Table}* steps = self.steps_of(seq, l);
	for (sz i = 0; i < q.elems.len(); i++)
	{
		Elem* el = &self.elems[q.elems[i]];
		sz cc = min(c, self.w);
		char pick = (*steps)[i].pick[cc];
		bool brk = i + 1 < q.elems.len() && c <= self.w ? (pick & 1) == 1 : false;
		if (c > self.w && i + 1 < q.elems.len()) brk = self.forced(q, i + 1, l);
		sz end;
		if (el.kind == SPAN)
		{
			Layout sl = (Layout)(pick >> 1);
			if (self.seqs[el.seq].magic) sl = STACK;
			self.read(el.seq, sl, c, breaks);
			(void)self.at(&(*self.layouts(q.elems[i]))[sl.ordinal], c, &end);
		}
		else
		{
			end = c + el.width;
		}
		if (i + 1 == q.elems.len()) break;
		sz next = self.elems[q.elems[i + 1]].first;
		if (brk)
		{
			(*breaks)[next - self.first] = true;
			c = self.target(q, i + 1);
		}
		else
		{
			c = end + self.join_w[next - self.first];
		}
	}
}

// ---- driver --------------------------------------------------------------------------------

<* Re-break the statements that need it (all of them in `fit`). *>
fn void Fmt.wrap(&self)
{
	if (self.cfg.line_breaks == PRESERVE || self.cfg.max_line_length == 0) return;
	Src* s = self.src;
	sz a = 0;
	while (a < s.len())
	{
		sz b = a;
		while (b + 1 < s.len() && !(self.out[b + 1].nl > 0 && !self.out[b + 1].cont)) b++;
		self.wrap_unit(a, b);
		a = b + 1;
	}
}

fn void Fmt.wrap_unit(&self, sz a, sz b)
{
	if (!self.wants_wrap(a, b)) return;
	@pool()
	{
		Wrap w;
		w.init(self, a, b);
		List{bool} breaks;
		breaks.tinit();
		for (sz k = a; k <= b; k++) breaks.push(false);
		w.solve_statement(&breaks);
		self.apply_breaks(&w, &breaks);
	};
}

<* Should the statement a..b be (re)wrapped? Statements with comments, compile-time blocks or an open block are left alone. *>
fn bool Fmt.wants_wrap(&self, sz a, sz b)
{
	Src* s = self.src;
	Config* c = self.cfg;
	if (b == a || b - a + 1 > c.wrap_budget) return false;
	bool too_long;
	for (sz k = a; k <= b; k++)
	{
		Tok* t = &s.toks[k];
		if (!t.code || t.keep || self.out[k].verbatim || t.text.contains("\n") || t.unterminated) return false;
		if (is_ct_open(t.type) || is_ct_end(t.type) || t.type == CT_ELSE || t.type == CT_CASE || t.type == CT_DEFAULT) return false;
		if (is_opener(t.type) && (t.match == NO || t.match > b)) return false;
		bool eol = k == b || self.out[k + 1].nl > 0;
		if (eol && self.end_col(k) > c.max_line_length) too_long = true;
	}
	if (c.line_breaks == LONG && !too_long) return false;
	return too_long || c.soft_max_line_length != 0 || !self.fits_as_is(a, b);
}

<* Measure the statement and build its elements. *>
fn void Wrap.init(&self, Fmt* f, sz a, sz b)
{
	Config* c = f.cfg;
	*self = {
		.f = f, .first = a, .last = b, .base = f.out[a].indent,
		.c0 = c.wrap_cost_soft, .c1 = c.wrap_cost_hard, .cb = c.wrap_cost_break,
		.m0 = c.soft_max_line_length, .m1 = c.max_line_length,
	};
	self.join_w.tinit();
	self.find_statements();
	for (sz k = a; k <= b; k++)
	{
		// an alignment gap counts as normal spacing: once the statement wraps it is not aligned anyway
		Out* o = &f.out[k];
		String j = k == a ? "" : o.nl == 0 && !o.anchor ? o.spacing : f.joined_spacing(k);
		// a tab in an alignment gap: its width where it is now
		self.join_w.push(j.contains("\t") ? text_width(j, f.prefix(k), c.tab_width) - f.prefix(k) : text_width(j, 0, 1));
	}
	// enough columns that no element of the statement ever starts past the table
	sz total = f.indent_width(self.base);
	for (sz k = a; k <= b; k++) total += text_width(f.src.toks[k].text, 0, c.tab_width) + self.join_w[k - a];
	self.w = max(c.max_line_length + SLACK_COLUMNS, total + 1);
	self.elems.tinit();
	self.seqs.tinit();
	self.top = self.build(a, b, 0);
	self.set_tails(self.top, 0);
	self.span_done.tinit();
	self.span_layouts.tinit();
	self.steps.tinit();
	for (sz q = 0; q < self.seqs.len(); q++)
	{
		self.span_done.push(false);
		self.span_layouts.push({});
		for (int l = 0; l < 3; l++) self.steps.push({});
	}
	foreach (&st : self.steps) st.tinit();
}

<* Choose the line breaks: the optimal layout, or the search (asked for, or the tables would be too big). *>
fn void Wrap.solve_statement(&self, List{bool}* breaks)
{
	sz start = self.f.indent_width(self.base);
	bool too_big = (sz)self.elems.len() * 3 * (self.w + 1) > MAX_CELLS;
	if (too_big)
	{
		// too long for the tables, and for the search to get far: fill the lines
		self.first_fit(start, breaks);
		return;
	}
	if (self.f.cfg.wrap_solver == SEARCH)
	{
		self.search(start, breaks);
		return;
	}
	(void)self.solve(self.top, INLINE);
	self.read(self.top, INLINE, start, breaks);
}

<* Write the chosen breaks into the layout, and decide the spacing again as the next run will see it. *>
fn void Fmt.apply_breaks(&self, Wrap* w, List{bool}* breaks)
{
	Src* s = self.src;
	sz a = w.first;
	sz b = w.last;
	List{sz} depth;
	depth.tinit();
	w.depths(breaks, &depth);
	for (sz k = a + 1; k <= b; k++)
	{
		Out* o = &self.out[k];
		bool brk = (*breaks)[k - a];
		o.nl = brk ? 1 : 0;
		if (brk)
		{
			o.cont = true;
			o.indent = w.base.deeper(depth[k - a]);
		}
		o.anchor = false;
		s.toks[k].nl = o.nl;   // the spacing rules look at line breaks
	}
	for (sz k = a + 1; k <= b; k++)
	{
		if ((*breaks)[k - a]) continue;
		String gap = s.gap(k);
		self.out[k].spacing = gap.contains("\n") ? self.joined_spacing(k) : self.apply(k, s.space_rule(k, self.cfg), gap);
	}
	// line starts moved: recompute which line each token is on
	for (sz k = a; k <= b; k++) self.out[k].line_tok = k == a || self.out[k].nl > 0 ? k : self.out[k - 1].line_tok;
}

<* A statement already on one line, with no trailing comma to stack: the solver would leave it so. *>
fn bool Fmt.fits_as_is(&self, sz a, sz b)
{
	Src* s = self.src;
	for (sz k = a + 1; k <= b; k++)
	{
		if (self.out[k].nl > 0) return false;
		if (self.cfg.magic_comma && is_closer(s.toks[k].type) && s.toks[k - 1].type == COMMA) return false;
	}
	return true;
}

<* Output column after token k with the current spacing. *>
fn sz Fmt.end_col(&self, sz k)
{
	sz col = self.prefix(k);
	if (k != self.out[k].line_tok) col = text_width(self.gap_text(k), col, self.cfg.tab_width);
	return text_width(self.src.toks[k].text, col, self.cfg.tab_width);
}

<* The spacing of gap k if the line break before token k is removed. *>
fn String Fmt.joined_spacing(&self, sz k)
{
	Space rule = self.src.space_rule(k, self.cfg);
	if (rule == KEEP)
	{
		// there was no spacing to keep: take what the stdlib writes most often here
		Config strict = *self.cfg;
		strict.spacing = STRICT;
		rule = self.src.space_rule(k, &strict);
	}
	if (rule == KEEP)
	{
		// nothing known about this context: parentheses and brackets hug, anything else gets a space
		TokenType p = self.src.toks[k - 1].type;
		TokenType n = self.src.toks[k].type;
		bool hug = p == LPAREN || p == LBRACKET || n == RPAREN || n == RBRACKET;
		rule = hug ? Space.NONE : Space.ONE;
	}
	return self.apply(k, rule, " ");
}

<*
 Indent level of each wrapped line, as layout will see it on the next run: a line broken inside
 brackets is one level deeper than the line its innermost open bracket is on (a closer at that
 line's level); a line broken outside brackets is one level deeper than the statement
 (a new element of an enclosing list: at its level).
*>
fn void Wrap.depths(&self, List{bool}* breaks, List{sz}* out)
{
	Src* s = self.f.src;
	out.clear();
	sz line_depth = 0;
	List{sz} opener_depth;
	opener_depth.tinit();
	for (sz k = self.first; k <= self.last; k++)
	{
		sz i = k - self.first;
		if (k > self.first && (*breaks)[i])
		{
			sz e = s.toks[k].encl;
			if (e == NO || e < self.first)
			{
				line_depth = self.list_comma(k) ? 0 : 1;
			}
			else
			{
				sz d = opener_depth[e - self.first];
				bool item = s.toks[k - 1].type == COMMA || k - 1 == e || is_closer(s.toks[k].type);
				// in a `{ … }` list a new item is a line of its own; the rest of an item goes deeper
				bool list = s.toks[e].type == LBRACE;
				line_depth = is_closer(s.toks[k].type) ? d : list && !item ? d + 2 : d + 1;
			}
		}
		out.push(line_depth);
		opener_depth.push(line_depth);
	}
}

// ---- dfmt's best-first search, as the alternative solver ------------------------------------

struct State @local
{
	List{sz} chosen;   // wrap points taken, in order
	float    cost;
	bool     fits;
}

<* The cost of a set of breaks; its scratch memory is freed again (the search calls it often). *>
fn float Wrap.simulate(&self, List{bool}* breaks, sz start, bool* fits) => @pool()
{
	return self.simulate_breaks(breaks, start, fits);
}

fn float Wrap.simulate_breaks(&self, List{bool}* breaks, sz start, bool* fits) @local
{
	Src* s = self.f.src;
	float cost;
	sz col = start;
	*fits = true;
	List{sz} depth;
	depth.tinit();
	self.depths(breaks, &depth);
	for (sz k = self.first; k <= self.last; k++)
	{
		sz i = k - self.first;
		if (k > self.first)
		{
			if ((*breaks)[i])
			{
				cost += self.cb * self.mult(self.point_kind(k), k, depth[i]);
				col = self.f.indent_width(self.base.deeper(depth[i]));
			}
			else
			{
				col += self.join_w[i];
			}
		}
		sz w = text_width(s.toks[k].text, 0, self.f.cfg.tab_width);
		cost += self.text_cost(col, w);
		col += w;
		if (col > self.m1) *fits = false;
	}
	return cost;
}

<* Fill the lines: when one gets too long, break at its outermost point (the last of those). *>
fn void Wrap.first_fit(&self, sz start, List{bool}* breaks) => @pool()
{
	foreach (&x : *breaks) *x = false;
	sz pending = NO;   // where the current line can still break: its outermost point so far
	for (sz k = self.first + 1; k <= self.last + 1; k++)
	{
		bool end = k > self.last;
		if (!end)
		{
			Point p = self.point_kind(k);
			if (p == NONE || p == CLOSE || self.blocked(k)) continue;
		}
		// the line runs up to token k - 1: too long, so break at the point kept
		if (pending != NO && self.end_column(breaks, start, k - 1) > self.m1)
		{
			(*breaks)[pending - self.first] = true;
			pending = NO;
		}
		if (!end && (pending == NO || self.nesting(k) <= self.nesting(pending))) pending = k;
	}
}

<* How many brackets of the statement enclose token k. *>
fn sz Wrap.nesting(&self, sz k) @local
{
	sz n;
	for (sz e = self.f.src.toks[k].encl; e != NO && e >= self.first; e = self.f.src.toks[e].encl) n++;
	return n;
}

<* Column after token k with these breaks. *>
fn sz Wrap.end_column(&self, List{bool}* breaks, sz start, sz k) @local => @pool()
{
	List{sz} depth;
	depth.tinit();
	self.depths(breaks, &depth);
	sz col = start;
	for (sz j = self.first; j <= k; j++)
	{
		sz i = j - self.first;
		if (j > self.first) col = (*breaks)[i] ? self.f.indent_width(self.base.deeper(depth[i])) : col + self.join_w[i];
		col += text_width(self.f.src.toks[j].text, 0, self.f.cfg.tab_width);
	}
	return col;
}

fn Point Wrap.point_kind(&self, sz k)
{
	Point p = self.point_before(k);
	if (p != NONE) return p;
	TokenType prev = self.f.src.toks[k - 1].type;
	if (is_opener(prev)) return OPEN;
	return is_closer(self.f.src.toks[k].type) ? Point.CLOSE : Point.NONE;
}

const int SEARCH_TRIES = 1000;
// layouts the search tries in all: each costs a copy of its breaks and a pass over the statement
const sz SEARCH_EXPANSIONS = 20_000;
const sz MAX_CELLS = 4_000_000;

<* Best-first search over sets of wrap points (dfmt's wrapping.d): cheapest set first, stop at the first that fits. *>
fn void Wrap.search(&self, sz start, List{bool}* breaks)
{
	List{sz} points;
	points.tinit();
	for (sz k = self.first + 1; k <= self.last; k++)
	{
		Point p = self.point_kind(k);
		if (p != NONE && p != CLOSE && !self.blocked(k)) points.push(k);
	}
	List{State} open;
	open.tinit();
	List{sz} none;
	none.tinit();
	bool fits;
	float c0 = self.simulate(breaks, start, &fits);
	open.push({none, c0, fits});
	State best = open[0];
	sz expansions;
	for (int tries = 0; tries < SEARCH_TRIES && open.len() && expansions < SEARCH_EXPANSIONS; tries++)
	{
		// take the cheapest open state
		sz bi = 0;
		foreach (i, st : open) if (st.cost < open[bi].cost) bi = i;
		State cur = open[bi];
		open.remove_at(bi);
		if (cur.fits)
		{
			best = cur;
			break;
		}
		if (cur.cost < best.cost) best = cur;
		// expand: add one more wrap point after the last one taken
		sz from = cur.chosen.len() ? cur.chosen[^1] : 0;
		foreach (p : points)
		{
			if (p <= from) continue;
			if (++expansions > SEARCH_EXPANSIONS) break;
			List{sz} next;
			next.tinit();
			foreach (x : cur.chosen) next.push(x);
			next.push(p);
			foreach (&x : *breaks) *x = false;
			foreach (x : next) (*breaks)[x - self.first] = true;
			float cost = self.simulate(breaks, start, &fits);
			open.push({next, cost, fits});
		}
	}
	foreach (&x : *breaks) *x = false;
	foreach (x : best.chosen) (*breaks)[x - self.first] = true;
}
