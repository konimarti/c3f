module c3f_test;
import c3f, std::io;

<* Formats `src`, compares with `want`, and checks that formatting again changes nothing. *>
fn void keeps(String src, String want) @local
{
	c3f::Config c = c3f::defaults();
	String got = fmt_with(src, &c);
	if (got != want) io::eprintfn("--- want ---\n%s--- got ---\n%s---", want, got);
	assert(got == want);
	String again = fmt_with(got, &c);
	if (again != got) io::eprintfn("--- not idempotent ---\n%s---", again);
	assert(again == got);
}

fn String body(String line) @local => "fn void f()\n{\n".tconcat(line).tconcat("\n}\n");

// ---- trailing blanks at the end of a `//` comment ----

fn void line_comment_loses_trailing_blanks() @test
{
	keeps(body("\t// trailing   "), body("\t// trailing"));
	keeps(body("\tfoo(); // a \t \t"), body("\tfoo(); // a"));
	keeps(body("\t/// doc  "), body("\t/// doc"));
	// the text stays as it is, also the blanks inside it
	keeps(body("\t// a   b \t c  "), body("\t// a   b \t c"));
}

fn void blank_line_comment_becomes_empty() @test
{
	keeps(body("\t//   "), body("\t//"));
	keeps(body("\t//\t"), body("\t//"));
}

fn void blanks_stay_where_the_source_is_kept() @test
{
	// off regions are copied as written
	keeps(body("\t// c3f off\n\t// kept   \n\t// c3f on"), body("\t// c3f off\n\t// kept   \n\t// c3f on"));
	// the inner lines of a block comment are not touched
	String s = body("\t/* a   \n\t   b   */");
	keeps(s, s);
}

fn void line_comment_blanks_with_crlf() @test
{
	c3f::Config c = c3f::defaults();
	String got = fmt_with("fn void f()\r\n{\r\n\t// a  \r\n\tx(); //   \r\n}\r\n", &c);
	assert(got == "fn void f()\r\n{\r\n\t// a\r\n\tx(); //\r\n}\r\n");
	// at the end of the file, without a line break
	assert(fmt_with("int x; // a  ", &c) == "int x; // a\n");
}
