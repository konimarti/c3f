module c3f_test;
import c3f, std::io;

<* A config: lines of at most `width` columns, broken as `breaks` says, lists as `lists` says. *>
fn c3f::Config lists_config(String lists, String breaks = "wrap", String width = "60") @local
{
	c3f::Config c = c3f::defaults();
	assert(@ok(c.set("max_line_length", width)));
	assert(@ok(c.set("c3f_line_breaks", breaks)));
	assert(@ok(c.set("c3f_wrap_lists", lists)));
	return c;
}

fn String in_fn(String line) @local => "fn void f()\n{\n".tconcat(line).tconcat("\n}\n");

const String CALL = "\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);";

fn void wrap_lists_fill_is_the_default() @test
{
	c3f::Config d = c3f::defaults();
	assert(d.wrap_lists == c3f::WrapLists.FILL);
	c3f::Config c = lists_config("fill");
	check(in_fn(CALL),
		in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc,\n\t\tdddddddddddd, eeeeeeeeeee);"), &c);
	// not set at all: the same
	c3f::Config e = c3f::defaults();
	assert(@ok(e.set("max_line_length", "60")));
	assert(@ok(e.set("c3f_line_breaks", "wrap")));
	check(in_fn(CALL),
		in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc,\n\t\tdddddddddddd, eeeeeeeeeee);"), &e);
}

fn void call_arguments_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	String want = in_fn("\tfoo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);");
	check(in_fn(CALL), want, &c);
	// the same in every mode that wraps
	c = lists_config("one_per_line", "wrap_rewrite");
	check(in_fn(CALL), want, &c);
	c = lists_config("one_per_line", "reflow");
	check(in_fn(CALL), want, &c);
	// with a value and an assignment in front
	check(in_fn("\tint x = foo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\tint x = foo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
}

fn void parameters_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	check("fn void long_name(int aaaaaaaaaaa, int bbbbbbbbbbbb, int ccccccccccccc, int ddddddddddd)\n{\n}\n",
		"fn void long_name(\n\tint aaaaaaaaaaa,\n\tint bbbbbbbbbbbb,\n\tint ccccccccccccc,\n\tint ddddddddddd\n)\n{}\n", &c);
	c3f::Config f = lists_config("fill");
	check("fn void long_name(int aaaaaaaaaaa, int bbbbbbbbbbbb, int ccccccccccccc, int ddddddddddd)\n{\n}\n",
		"fn void long_name(int aaaaaaaaaaa, int bbbbbbbbbbbb,\n\tint ccccccccccccc, int ddddddddddd)\n{}\n", &f);
}

fn void initializers_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	check(in_fn("\tint[] t = { aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee };"),
		in_fn("\tint[] t = {\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t};"), &c);
	// designated initializers
	check(in_fn("\tFoo f = { .a = aaaaaaaaaaa, .b = bbbbbbbbbbbb, .c = ccccccccccccc, .d = dddddddddddd };"),
		in_fn("\tFoo f = {\n\t\t.a = aaaaaaaaaaa,\n\t\t.b = bbbbbbbbbbbb,\n\t\t.c = ccccccccccccc,\n\t\t.d = dddddddddddd\n\t};"), &c);
}

fn void macro_calls_and_calls_in_conditions_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	check(in_fn("\t@foo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\t@foo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
	check(in_fn("\treturn foo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\treturn foo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
}

fn void a_list_that_fits_stays_on_its_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	check(in_fn("\tfoo(a, b, c);"), in_fn("\tfoo(a, b, c);"), &c);
	check(in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, ddddddd);"), in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, ddddddd);"), &c);
	// reflow joins a break made by hand when the list fits
	c = lists_config("one_per_line", "reflow");
	check(in_fn("\tfoo(a,\n\t\tb,\n\t\tc);"), in_fn("\tfoo(a, b, c);"), &c);
}

fn void only_the_lists_that_must_wrap_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	// the inner call fits on its line: it stays whole while the outer list is stacked
	check(in_fn("\tx = outer(inner(aaaaaaaaaaa, bbbbbbbbbbbb), ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\tx = outer(\n\t\tinner(aaaaaaaaaaa, bbbbbbbbbbbb),\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
	// both levels need it
	check(in_fn("\tx = outer(inner(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd), eeeeeeeeeee, fffffffffff);"),
		in_fn("\tx = outer(\n\t\tinner(\n\t\t\taaaaaaaaaaa,\n\t\t\tbbbbbbbbbbbb,\n\t\t\tccccccccccccc,\n\t\t\tdddddddddddd\n\t\t),\n\t\teeeeeeeeeee,\n\t\tfffffffffff\n\t);"), &c);
}

fn void a_parenthesized_expression_or_a_loop_header_is_no_list() @test
{
	c3f::Config c = lists_config("one_per_line");
	check(in_fn("\tfor (int i = 0, j = 1; i < aaaaaaaaaaaaaaaaaaaaaaaaaaa && j < bbbbbbbbbbbbbbbbbbbb; i++) x();"),
		in_fn("\tfor (int i = 0, j = 1; i < aaaaaaaaaaaaaaaaaaaaaaaaaaa\n\t\t&& j < bbbbbbbbbbbbbbbbbbbb; i++) x();"), &c);
	// a single argument is no list: it is laid out as before
	c3f::Config f = lists_config("fill");
	String single = in_fn("\tx = foo(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa + bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb);");
	assert(fmt_with(single, &c) == fmt_with(single, &f));
}

fn void keep_and_no_limit_change_nothing() @test
{
	String src = in_fn(CALL);
	c3f::Config c = lists_config("one_per_line", "keep");
	check(src, src, &c);
	c3f::Config n = c3f::defaults();
	assert(@ok(n.set("c3f_line_breaks", "wrap")));
	assert(@ok(n.set("c3f_wrap_lists", "one_per_line")));
	check(src, src, &n);
}

fn void no_comma_is_added_or_removed() @test
{
	c3f::Config c = lists_config("one_per_line");
	String out = fmt_with(in_fn(CALL), &c);
	assert(!out.contains("eeeeeeeeeee,"));
	// a list that has a trailing comma keeps it (and one item per line, as before)
	String trailing = in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee,);");
	String want = in_fn("\tfoo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee,\n\t);");
	check(trailing, want, &c);
	// also when it would fit (reflow lays a statement out again)
	c3f::Config r = lists_config("one_per_line", "reflow");
	check(in_fn("\tfoo(a, b,);"), in_fn("\tfoo(\n\t\ta,\n\t\tb,\n\t);"), &r);
	// with the magic comma off the trailing comma is only a token
	assert(@ok(c.set("c3f_magic_comma", "false")));
	check(in_fn("\tfoo(a, b,);"), in_fn("\tfoo(a, b,);"), &c);
}

fn void one_per_line_output_is_stable_in_every_mode() @test
{
	String call = in_fn("\tx = aaaa(bbbbbbbbbbbbbbbb, cccccccccccccccccccccccccccccccc, dddddddddd(eeeeeeeeeeeeeeee, ffffffffffffffff, gggggggggggggggg, hhhhhhhhhhhhhh));");
	foreach (String breaks : { "wrap", "wrap_rewrite", "reflow" })
	{
		foreach (String cont : { "keep", "indent", "align" })
		{
			c3f::Config c = lists_config("one_per_line", breaks, "50");
			assert(@ok(c.set("c3f_continuation", cont)));
			String once = fmt_with(call, &c);
			assert(fmt_with(once, &c) == once, "not idempotent (%s, %s):\n%s", breaks, cont, once);
		}
	}
}

fn void wrap_lists_rejects_a_bad_value() @test
{
	c3f::Config c = c3f::defaults();
	assert(@catch(c.set("c3f_wrap_lists", "sideways")) == c3f::BAD_VALUE);
	assert(@catch(c.set("c3f_wrap_lists", "one")) == c3f::BAD_VALUE);
	assert(c.wrap_lists == c3f::WrapLists.FILL);
	assert(@ok(c.set("c3f_wrap_lists", "ONE_PER_LINE")));
	assert(c.wrap_lists == c3f::WrapLists.ONE_PER_LINE);
	assert(c.value_text(c3f::Key.WRAP_LISTS) == "one_per_line");
	assert(c3f::allowed_values(c3f::Key.WRAP_LISTS) == "fill, one_per_line");
}

fn void ternaries_wrap_at_their_question_mark_and_colon() @test
{
	String[] modes = { "wrap", "reflow" };
	foreach (mode : modes)
	{
		c3f::Config cfg = c3f::defaults();
		assert(@ok(cfg.set("max_line_length", "80")));
		assert(@ok(cfg.set("c3f_line_breaks", mode)));
		String src = "fn int f()\n{\n\treturn condition_one_is_true_here ? some_value_when_true_expression : some_other_value_when_false;\n}\n";
		String got = fmt_with(src, &cfg);
		assert(got == "fn int f()\n{\n\treturn condition_one_is_true_here ? some_value_when_true_expression\n\t\t: some_other_value_when_false;\n}\n", "got:\n%s", got);
		assert(fmt_with(got, &cfg) == got);
		// in an assignment, and inside an argument list: the ternary breaks, not the other arguments
		src = "fn void g()\n{\n\tint result_value = condition_flag_variable ? first_alternative_value_name : second_alternative_value_nm;\n}\n";
		got = fmt_with(src, &cfg);
		assert(got == "fn void g()\n{\n\tint result_value = condition_flag_variable ? first_alternative_value_name\n\t\t: second_alternative_value_nm;\n}\n", "got:\n%s", got);
		src = "fn void g()\n{\n\tfoo(condition_one_is_true_here ? some_value_when_true_expression : some_other_value_when_false, 1, 2);\n}\n";
		got = fmt_with(src, &cfg);
		assert(got == "fn void g()\n{\n\tfoo(condition_one_is_true_here ? some_value_when_true_expression\n\t\t: some_other_value_when_false, 1, 2);\n}\n", "got:\n%s", got);
		assert(fmt_with(got, &cfg) == got);
	}
}

fn void nested_ternaries_and_other_colons_stay_stable() @test
{
	String src = "fn int f(int c)\n{\n"
		"\tx = a_condition ? first_option_value_here_long : b_condition ? second_option_value_here_long : third_option_value_long;\n"
		"\treturn condition_one_is_true_here ? some_value_when_true_expression : (other_cond ? nested_one_value_long : nested_two_long);\n"
		"\tswitch (value_of_the_thing_to_switch_on_long_name_here)\n\t{\n"
		"\t\tcase SOME_LONG_CONSTANT_NAME_NUMBER_ONE: return a_condition_value ? first_option_value : second_option_value_long;\n\t}\n"
		"\tint? result = some_function_returning_an_optional_value(argument_one, argument_two) ?? other_fallback_value_here;\n"
		"\tfoo(fn int(int q) => q ? first_alternative_value_name_long : second_alternative_value_name_long, c ? 1 : 2);\n"
		"}\n";
	String[] modes = { "wrap", "reflow" };
	String[] widths = { "40", "60", "80", "100" };
	foreach (mode : modes)
	{
		foreach (w : widths)
		{
			c3f::Config cfg = c3f::defaults();
			assert(@ok(cfg.set("max_line_length", w)));
			assert(@ok(cfg.set("c3f_line_breaks", mode)));
			String once = fmt_with(src, &cfg);
			assert(fmt_with(once, &cfg) == once, "not idempotent at %s:\n%s", w, once);
			String a = src.treplace("\n", "").treplace("\t", "").treplace(" ", "");
			String b = once.treplace("\n", "").treplace("\t", "").treplace(" ", "");
			assert(a == b, "tokens changed:\n%s", once);
		}
	}
}

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
