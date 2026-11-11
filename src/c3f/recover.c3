module c3f;

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
