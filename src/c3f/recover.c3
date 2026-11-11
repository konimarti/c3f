module c3f;
import c3::lexer;

<*
 Where a damaged file is picked up again: a line that starts at column 0 with one of these words (or
 with the `<*` of a doc comment, which belongs to the declaration after it) begins a top-level
 declaration. `$if` and the other `$` keywords are not in it: code may write them flush left inside
 a function. The list is the compiler's keywords (`c3_search` scope=syntax) that only start a
 declaration at the top level; `static`, `tlocal` and `inline` also occur in function bodies.
*>
const String[] BREAK_WORDS = {
	"fn", "macro", "struct", "union", "enum", "bitstruct", "interface", "faultdef", "alias",
	"typedef", "const", "module", "import", "extern", "attrdef", "attrmacro", "constdef", "constset"
};

fn bool is_ident_byte(char c) => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';

<* Does the line starting at byte `pos` begin a top-level declaration? A word counts as a whole word only. *>
fn bool is_break_line(String text, sz pos)
{
	String rest = text[pos..];
	if (rest.starts_with("<*")) return true;
	foreach (w : BREAK_WORDS)
	{
		if (!rest.starts_with(w)) continue;
		if (rest.len == w.len || !is_ident_byte(rest[w.len])) return true;
	}
	return false;
}

<* Start of the first line after the line holding byte `from` that is a break line, or NO. *>
fn sz find_break(String text, sz from)
{
	sz k = from;
	while (true)
	{
		while (k < text.len && text[k] != '\n') k++;
		if (k >= text.len) return NO;
		k++;
		if (k < text.len && is_break_line(text, k)) return k;
	}
}

<* Is token t, at byte offset `start` of its line, a break point? *>
fn bool is_break_token(Tok* t, bool at_line_start)
{
	if (!at_line_start) return false;
	switch (t.type)
	{
		case FUNC: case MACRO: case STRUCT: case UNION: case ENUM: case BITSTRUCT: case INTERFACE:
		case FAULTDEF: case ALIAS: case TYPEDEF: case CONST: case MODULE: case IMPORT: case EXTERN:
		case ATTRDEF: case ATTRMACRO: case CONSTDEF: case CONSTSET:
			return true;
		case CONTRACT:
			return t.text.starts_with("<*");
		default:
			return false;
	}
}

<* The cause of an unterminated token that runs to the end of the input, or "". *>
fn String unterminated_cause(Token* t)
{
	if (!t.unterminated) return "";
	switch (t.type)
	{
		case STRING: return t.text.starts_with("`") ? "unterminated raw string" : "";
		case BLOCK_COMMENT: return "unterminated comment";
		case CONTRACT: return "unterminated doc comment";
		default: return "";
	}
}

<*
 The lexer, with a recovery: a raw string, block comment or doc comment that is never closed ends just
 before the next break line (without the whitespace in front of it), and lexing goes on there. The
 offsets and lines of the tokens after it are those of the whole text.
*>
struct Recovering
{
	Lexer  lx;
	String text;
	sz     base;        // offset of the text the lexer has
	sz     line_add;    // lines before it
	sz     first_nl;    // newlines before the first token after a cut, or NO
	bool   cut;         // the token returned last was cut short
	sz     last_line;   // then: the line of its last byte
}

fn void Recovering.init(&self, String text)
{
	*self = { .text = text, .first_nl = NO };
	self.lx.init(text);
}

fn Token? Recovering.next(&self)
{
	Token t = self.lx.next()!;
	self.cut = false;
	t.offset += self.base;
	t.ln += self.line_add;
	if (self.first_nl != NO)
	{
		t.nl_before = self.first_nl;
		self.first_nl = NO;
	}
	if (unterminated_cause(&t).len == 0) return t;
	sz bp = find_break(self.text, t.offset);
	self.last_line = t.ln + t.text.count("\n");
	if (bp == NO) return t;
	sz e = bp;
	while (e > t.offset && (self.text[e - 1] == ' ' || self.text[e - 1] == '\t' || self.text[e - 1] == '\r' || self.text[e - 1] == '\n')) e--;
	String gap = self.text[e:bp - e];
	t.text = self.text[t.offset:e - t.offset];
	t.len = t.text.len;
	self.last_line = t.ln + t.text.count("\n");
	self.cut = true;
	self.first_nl = gap.count("\n");
	self.line_add = t.ln + self.text[t.offset:bp - t.offset].count("\n") - 1;
	self.base = bp;
	self.lx.init(self.text[bp..]);
	return t;
}
