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

fn void unterminated_raw_string() @test
{
	// the part of the function before the string is formatted too; the string and what follows are as written
	recovered("fn void a()\n{\n  int b=1;\n  String s = `abc;\n  foo( );\n}\n".tconcat(TAIL),
		"fn void a()\n{\n\tint b = 1;\n\tString s = `abc;\n  foo( );\n}\n".tconcat(TAIL_OUT),
		{ "unterminated raw string; kept as written up to line 6" }, { 4 });
}

<*
 A block comment that runs to the end of the file is valid (c3c reads the rest as a comment): kept to
 the end as before, with no note of its own, no fallback, and `--check` exits 0.
*>
fn void block_comment_to_the_end_of_the_file_is_valid() @test
{
	c3f::Config d = c3f::defaults();
	String[] files = {
		"module m;\n/*\nfn void a()\n{\n  foo( );\n}\n",
		"module m;\n/*\n/* nested */\nfn void a()\n{\n  foo( );\n}\n",
		"fn void z()\n{\n  q=1;\n}\n/* a /* b */\nfn void a()\n{\n  foo( );\n}\n",
	};
	foreach (src : files)
	{
		c3f::FormatResult r = c3f::format(tmem, src, &d);
		assert(!r.fallback && r.notes.len() == 0, "for %s", src);
		assert(squash(r.text) == squash(src));
		// the comment is kept as written
		assert(r.text.contains("/*") && r.text.contains("fn void a()\n{\n  foo( );\n}\n"), "for %s", r.text);
		cli::Options opt;
		opt.mode = CHECK;
		cli::Status st = cli::run(&opt, "x.c3", src, &d);
		assert(st == cli::Status.OK || st == cli::Status.CHANGED, "for %s", src);
		assert(st != cli::Status.KEPT);
	}
	// nothing but the part before the comment changes
	c3f::FormatResult r = c3f::format(tmem, files[2], &d);
	assert(r.text.starts_with("fn void z()\n{\n\tq = 1;\n}\n/* a /* b */"));
}

fn void unterminated_doc_comment_before_a_function() @test
{
	recovered("<* doc\nfn void a()\n{\n  foo( );\n}\n", "<* doc\nfn void a()\n{\n\tfoo();\n}\n",
		{ "unterminated doc comment; kept as written up to line 1" }, { 1 });
}

fn void unterminated_doc_comment_at_the_end() @test
{
	recovered("fn void a() {}\n<* doc\n  foo( );\n", "fn void a() {}\n<* doc\n  foo( );\n",
		{ "unterminated doc comment; kept as written to the end of the file" }, { 2 });
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

fn void a_terminated_doc_comment_is_fine() @test
{
	c3f::Config d = c3f::defaults();
	c3f::FormatResult r = c3f::format(tmem, "fn void a() {}\n<* doc *>\nfn void b(){}\n", &d);
	assert(!r.fallback && r.notes.len() == 0);
	assert(r.text == "fn void a() {}\n<* doc *>\nfn void b() {}\n");
}

fn void two_errors_two_notes() @test
{
	recovered("const X = foo(1, 2;\nfn void a()\n{\n\tint s = `abc;\n}\n\nfn void z()\n{\n  q=1;\n}\n",
		"const X = foo(1, 2;\nfn void a()\n{\n\tint s = `abc;\n}\n\nfn void z()\n{\n\tq = 1;\n}\n",
		{ "unclosed '('; kept as written up to line 1", "unterminated raw string; kept as written up to line 5" }, { 1, 4 });
}

fn void crlf_file() @test
{
	recovered("fn void a()\r\n{\r\n\tint s = `abc;\r\n}\r\n\r\nfn void z()\r\n{\r\n  q=1+2;\r\n}\r\n",
		"fn void a()\r\n{\r\n\tint s = `abc;\r\n}\r\n\r\nfn void z()\r\n{\r\n\tq = 1 + 2;\r\n}\r\n",
		{ "unterminated raw string; kept as written up to line 4" }, { 3 });
}

fn void check_exits_3_for_every_recovery() @test
{
	c3f::Config cfg = c3f::defaults();
	cli::Options opt;
	opt.mode = CHECK;
	String[] damaged = {
		"fn void a()\n{\n\tif (x) {\n}\n\nfn void z() {}\n",
		"const X = foo(1;\n",
		"fn void a()\n{\n\tString s = `abc;\n}\n\nfn void z() {}\n",
		"fn void z() {}\n<* doc\n",
		"fn void z() {}\n<* doc\nfn void y() {}\n",
	};
	foreach (src : damaged) assert(cli::run(&opt, "damaged.c3", src, &cfg) == cli::Status.KEPT, "for %s", src);
}
