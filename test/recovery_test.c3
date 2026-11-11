module c3f_test;
import c3f, c3f::cli, std::io;

// what follows every damaged place: a correct function, which must come out formatted
const String TAIL = "\nfn void z()\n{\n  q=1+2;\n}\n";
const String TAIL_OUT = "\nfn void z()\n{\n\tq = 1 + 2;\n}\n";

<* The text without its spaces, tabs and newlines: nothing may be added, removed or changed. *>
fn String squash(String s) @local
{
	DString d;
	d.tinit();
	foreach (c : s) if (c != ' ' && c != '\t' && c != '\n' && c != '\r') d.append(c);
	return d.str_view();
}

<*
 Formats damaged `src`: the result is `want`, the same tokens, the same again, and the notes are
 `notes` (line, text).
*>
fn void recovered(String src, String want, String[] notes, sz[] lines) @local
{
	c3f::Config d = c3f::defaults();
	c3f::FormatResult r = c3f::format(tmem, src, &d);
	if (r.text != want) io::eprintfn("--- want ---\n%s--- got ---\n%s---", want, r.text);
	assert(r.text == want);
	assert(squash(r.text) == squash(src));
	assert(r.fallback);
	if (r.notes.len() != notes.len) foreach (n : r.notes) io::eprintfn("note %d: %s", n.line, n.text);
	assert(r.notes.len() == notes.len);
	foreach (i, n : notes)
	{
		assert(r.notes[i].text == n, "note %d: %s", i, r.notes[i].text);
		assert(r.notes[i].line == lines[i]);
	}
	c3f::FormatResult again = c3f::format(tmem, r.text, &d);
	assert(again.text == r.text, "not idempotent: %s", again.text);
}

fn void unclosed_brace_in_a_function() @test
{
	recovered("fn void a()\n{\n\tif (x) {\n\t\tfoo();\n}\n".tconcat(TAIL), "fn void a()\n{\n\tif (x) {\n\t\tfoo();\n}\n".tconcat(TAIL_OUT),
		{ "unclosed '{'; kept as written up to line 5" }, { 2 });
}

fn void unclosed_paren_at_top_level() @test
{
	recovered("const X = foo(1, 2;\n".tconcat(TAIL), "const X = foo(1, 2;\n".tconcat(TAIL_OUT),
		{ "unclosed '('; kept as written up to line 1" }, { 1 });
}

fn void unclosed_bracket() @test
{
	recovered("int[ x = 3;\n".tconcat(TAIL), "int[ x = 3;\n".tconcat(TAIL_OUT),
		{ "unclosed '['; kept as written up to line 1" }, { 1 });
}

fn void no_break_point_keeps_the_rest() @test
{
	recovered("const X = foo(1, 2;\n  int y=1;\n", "const X = foo(1, 2;\n  int y=1;\n",
		{ "unclosed '('; kept as written to the end of the file" }, { 1 });
}

fn void ct_keywords_flush_left_are_no_break_point() @test
{
	String src = "fn void a()\n{\n\tif (x) {\n$if X:\n\tfoo( );\n$endif\n}\n".tconcat(TAIL);
	recovered(src, "fn void a()\n{\n\tif (x) {\n$if X:\n\tfoo( );\n$endif\n}\n".tconcat(TAIL_OUT),
		{ "unclosed '{'; kept as written up to line 7" }, { 2 });
}

fn void a_lambda_is_no_break_point() @test
{
	String src = "fn void a()\n{\n\tif (x) {\n\t\tfn void() f = fn void() {};\n\tfn void() g = fn void( ) {};\n}\n".tconcat(TAIL);
	recovered(src, "fn void a()\n{\n\tif (x) {\n\t\tfn void() f = fn void() {};\n\tfn void() g = fn void( ) {};\n}\n".tconcat(TAIL_OUT),
		{ "unclosed '{'; kept as written up to line 6" }, { 2 });
}

fn void a_word_that_starts_with_a_keyword_is_no_break_point() @test
{
	recovered("const X = foo(1, 2;\nfnord  y=1;\n".tconcat(TAIL), "const X = foo(1, 2;\nfnord  y=1;\n".tconcat(TAIL_OUT),
		{ "unclosed '('; kept as written up to line 2" }, { 1 });
}
