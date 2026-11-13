module c3f_test;
import c3f, std::collections::list, std::io;

<* The width of a line's indentation, tabs counted as `tw` columns. *>
fn sz indent_width(String line, sz tw) @local
{
	sz w;
	foreach (c : line)
	{
		if (c == '\t')
		{
			w = (w / tw + 1) * tw;
		}
		else if (c == ' ')
		{
			w++;
		}
		else
		{
			break;
		}
	}
	return w;
}

fn sz line_with(String[] lines, String marker) @local
{
	foreach (i, l : lines) if (l.trim().starts_with(marker)) return i;
	unreachable("no line with %s", marker);
}

<*
 A header that goes over two lines and ends in '{' (K&R and linux braces): the body is one level
 in from the line the header starts on, and the '}' is in its column, whatever the continuation
 line's own indent is.
*>
fn void check_header(String first, String cont, String body, String open_line, String[] settings, sz tw, sz unit) @local
{
	String src = string::tformat("fn void g()\n{\n\t%s\n\t\t\t%s\n\t\t%s\n\t}\n}\n", first, cont, body);
	c3f::Config cfg = c3f::defaults();
	for (sz i = 0; i + 1 < settings.len; i += 2) (void)cfg.set(settings[i], settings[i + 1]);
	String once = fmt_with(src, &cfg);
	assert(fmt_with(once, &cfg) == once, "not idempotent:\n%s", once);
	String[] lines = once.tsplit("\n");
	sz head = line_with(lines, open_line);
	sz b = line_with(lines, body);
	sz hw = indent_width(lines[head], tw);
	assert(indent_width(lines[b], tw) == hw + unit, "body of '%s' in:\n%s", first, once);
	assert(indent_width(lines[b + 1], tw) == hw, "closing brace of '%s' in:\n%s", first, once);
}

fn void braces_after_a_continued_header_follow_the_statement() @test
{
	String[][] styles = {
		{ "c3f_style", "knr" },
		{ "c3f_brace_style", "linux" },
	};
	String[] continuations = { "keep", "indent", "align" };
	foreach (st : styles)
	{
		foreach (cont : continuations)
		{
			// tabs, and spaces with a tab width that is not the indent width
			String[][] indents = {
				{ "indent_style", "tab" },
				{ "indent_style", "space", "tab_width", "8", "indent_size", "4" },
			};
			foreach (ind : indents)
			{
				List{String} l;
				l.tinit();
				l.push(st[0]);
				l.push(st[1]);
				l.push("c3f_continuation");
				l.push(cont);
				foreach (x : ind) l.push(x);
				String[] set = l.array_view();
				sz tw = ind.len > 2 ? 8 : 4;
				sz unit = 4;
				check_header("if (a &&", "b) {", "body();", "if (a", set, tw, unit);
				check_header("while (a &&", "b) {", "body();", "while (a", set, tw, unit);
				check_header("foreach (i,", "v : list) {", "body();", "foreach (i", set, tw, unit);
				check_header("for (int i = 0;", "i < 3; i++) {", "body();", "for (int", set, tw, unit);
				check_header("struct Foo @align(", "4) {", "int a;", "struct Foo", set, tw, unit);
			}
		}
	}
}

<* Formats `src`, compares with `want`, and checks that formatting again changes nothing. *>
fn void expect(String src, String want, c3f::Config* cfg) @local
{
	String got = fmt_with(src, cfg);
	assert(got == want, "want:\n%s\ngot:\n%s", want, got);
	assert(fmt_with(got, cfg) == got, "not idempotent:\n%s", got);
}

fn void top_level_function_headers_and_lambdas() @test
{
	c3f::Config knr = c3f::defaults();
	(void)knr.set("c3f_style", "knr");
	expect("fn void f(int a,\n\t\tint b) {\n\tx();\n}\n", "fn void f(int a,\n\t\tint b) {\n\tx();\n}\n", &knr);
	expect("fn void f(int a,\n    int b) {\n    x();\n}\n", "fn void f(int a,\n    int b) {\n\tx();\n}\n", &knr);
	c3f::Config linux = c3f::defaults();
	(void)linux.set("c3f_brace_style", "linux");
	expect("fn void f(int a,\n\t\tint b) {\n\tx();\n}\n", "fn void f(int a,\n\t\tint b)\n{\n\tx();\n}\n", &linux);
	// a lambda body in an argument list keeps its layout
	expect("fn void f()\n{\n\tfoo(a,\n\t\tfn void() {\n\t\t\tx();\n\t\t}, b);\n\tfoo(fn void(int q) {\n\t\ty();\n\t});\n}\n",
	      "fn void f() {\n\tfoo(a,\n\t\tfn void() {\n\t\t\tx();\n\t\t}, b);\n\tfoo(fn void(int q) {\n\t\ty();\n\t});\n}\n", &knr);
}
