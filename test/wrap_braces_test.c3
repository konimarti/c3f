module c3f_test;
import c3f, std::io;

fn void headers_that_end_in_a_brace_wrap() @test
{
	String fn_header = "fn int compute_value_of_things(int first_argument, int second_argument, int third_argument, int fourth) {\n\treturn 1;\n}\n";
	foreach (mode : (String[]){ "wrap", "reflow" })
	{
		String got = settled(fn_header, { "c3f_style", "knr", "max_line_length", "80", "c3f_line_breaks", mode, "c3f_continuation", "indent" });
		assert(got == "fn int compute_value_of_things(int first_argument, int second_argument,\n\tint third_argument, int fourth) {\n\treturn 1;\n}\n", "got:\n%s", got);
		// linux: a function's brace is on its own line, as with allman
		got = settled(fn_header, { "c3f_brace_style", "linux", "max_line_length", "80", "c3f_line_breaks", mode });
		assert(got == "fn int compute_value_of_things(int first_argument, int second_argument,\n\tint third_argument, int fourth)\n{\n\treturn 1;\n}\n", "got:\n%s", got);
	}
	String ifs = "fn void g()\n{\n\tif (first_argument > second_argument && third_argument < fourth || some_flag_variable && another_flag) {\n\t\ty();\n\t}\n}\n";
	foreach (style : (String[]){ "knr", "linux" })
	{
		String[] set = { style == "knr" ? "c3f_style" : "c3f_brace_style", style, "max_line_length", "80", "c3f_line_breaks", "wrap" };
		String got = settled(ifs, set);
		String[] lines = got.tsplit("\n");
		foreach (l : lines) assert(indent_text_width(l) <= 80, "a line over the limit in:\n%s", got);
		assert(got.contains("\n\t\t|| some_flag_variable && another_flag) {\n\t\ty();\n\t}\n"), "got:\n%s", got);
	}
	// the brace counts for the width of the last line: this one fits only without it
	String tight = "fn void g()\n{\n\twhile (aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa && bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb) {\n\t\ty();\n\t}\n}\n";
	String got = settled(tight, { "c3f_style", "knr", "max_line_length", "80", "c3f_line_breaks", "wrap" });
	foreach (l : got.tsplit("\n")) assert(indent_text_width(l) <= 80, "a line over the limit in:\n%s", got);
	// reflow joins a header written over two lines when it fits with its brace
	got = settled("fn void g()\n{\n\twhile (a &&\n\t\tb) {\n\t\tv();\n\t}\n}\n", { "c3f_style", "knr", "max_line_length", "80", "c3f_line_breaks", "reflow" });
	assert(got == "fn void g() {\n\twhile (a && b) {\n\t\tv();\n\t}\n}\n", "got:\n%s", got);
}

<* The width of a line with tabs as 4 columns. *>
fn sz indent_text_width(String line) @local
{
	sz w;
	foreach (c : line) w = c == '\t' ? (w / 4 + 1) * 4 : w + 1;
	return w;
}

<* A damaged or switched-off region is kept as it was written, even a header in it that ends in `{`. *>
fn void damaged_regions_are_kept_with_wrapped_headers() @test
{
	String long_header = "fn void f(int very_long_argument_name, int another_very_long_argument_name) {";
	String if_header = "\tif (aaaaaaaaaaaaaaaaaaa && bbbbbbbbbbbbbbbbbbbbbb && cccccccccccccc) {";
	String[] sources = {
		// an unclosed '{' ends the file
		string::tformat("module m;\n%s\n\treturn 1;\n", long_header),
		string::tformat("module m;\nfn void f()\n{\n%s\n\t\treturn 1;\n", if_header),
		// an unclosed '(' or '[' in a header
		"module m;\nfn void f()\n{\n\tif (aaaaaaaaaaaaaaaaaaa && bbbbbbbbbbbbbbbbbbbbbb && (cccccccccccccc) {\n\t\treturn 1;\n\t}\n}\n",
		"module m;\nfn void f(int very_long_argument_name, int another_very_long_argument_name[ {\n\treturn 1;\n}\n",
		// switched off
		string::tformat("// c3f off\n%s\n%s\n\t\treturn 1;\n\t}\n}\n// c3f on\n", long_header, if_header),
	};
	foreach (src : sources)
	{
		foreach (style : (String[]){ "c3f_style", "c3f_brace_style" })
		{
			String kind = style == "c3f_style" ? "knr" : "linux";
			c3f::Config plain = c3f::defaults();
			assert(@ok(plain.set(style, kind)));
			String expected = fmt_with(src, &plain);
			foreach (mode : (String[]){ "wrap", "reflow" })
			{
				c3f::Config cfg = c3f::defaults();
				assert(@ok(cfg.set(style, kind)));
				assert(@ok(cfg.set("max_line_length", "40")));
				assert(@ok(cfg.set("c3f_line_breaks", mode)));
				String got = fmt_with(src, &cfg);
				assert(got == expected, "changed:\n%s", got);
			}
		}
	}
}
