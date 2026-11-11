module c3f_test;
import c3f, std::io;

<* A config: lines of at most `width` columns, broken as `breaks` says, lists as `lists` says. *>
fn c3f::Config lists_config(String lists, String breaks = "wrap", String width = "60") @local
{
	c3f::Config c = c3f::defaults();
	(void)c.set("max_line_length", width);
	(void)c.set("c3f_line_breaks", breaks);
	(void)c.set("c3f_wrap_lists", lists);
	return c;
}

<* Formats `src`, compares with `want`, and checks that formatting again changes nothing. *>
fn void lists_check(String src, String want, c3f::Config* cfg) @local
{
	String got = fmt_with(src, cfg);
	if (got != want) io::eprintfn("--- want ---\n%s--- got ---\n%s---", want, got);
	assert(got == want);
	String again = fmt_with(got, cfg);
	if (again != got) io::eprintfn("--- not idempotent ---\n%s---", again);
	assert(again == got);
}

fn String in_fn(String line) @local => "fn void f()\n{\n".tconcat(line).tconcat("\n}\n");

const String CALL = "\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);";

fn void wrap_lists_fill_is_the_default() @test
{
	c3f::Config d = c3f::defaults();
	assert(d.wrap_lists == c3f::WrapLists.FILL);
	c3f::Config c = lists_config("fill");
	lists_check(in_fn(CALL),
		in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc,\n\t\tdddddddddddd, eeeeeeeeeee);"), &c);
	// not set at all: the same
	c3f::Config e = c3f::defaults();
	(void)e.set("max_line_length", "60");
	(void)e.set("c3f_line_breaks", "wrap");
	lists_check(in_fn(CALL),
		in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc,\n\t\tdddddddddddd, eeeeeeeeeee);"), &e);
}

fn void call_arguments_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	String want = in_fn("\tfoo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);");
	lists_check(in_fn(CALL), want, &c);
	// the same in every mode that wraps
	c = lists_config("one_per_line", "wrap_rewrite");
	lists_check(in_fn(CALL), want, &c);
	c = lists_config("one_per_line", "reflow");
	lists_check(in_fn(CALL), want, &c);
	// with a value and an assignment in front
	lists_check(in_fn("\tint x = foo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\tint x = foo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
}

fn void parameters_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	lists_check("fn void long_name(int aaaaaaaaaaa, int bbbbbbbbbbbb, int ccccccccccccc, int ddddddddddd)\n{\n}\n",
		"fn void long_name(\n\tint aaaaaaaaaaa,\n\tint bbbbbbbbbbbb,\n\tint ccccccccccccc,\n\tint ddddddddddd\n)\n{\n}\n", &c);
	c3f::Config f = lists_config("fill");
	lists_check("fn void long_name(int aaaaaaaaaaa, int bbbbbbbbbbbb, int ccccccccccccc, int ddddddddddd)\n{\n}\n",
		"fn void long_name(int aaaaaaaaaaa, int bbbbbbbbbbbb,\n\tint ccccccccccccc, int ddddddddddd)\n{\n}\n", &f);
}

fn void initializers_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	lists_check(in_fn("\tint[] t = { aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee };"),
		in_fn("\tint[] t = {\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t};"), &c);
	// designated initializers
	lists_check(in_fn("\tFoo f = { .a = aaaaaaaaaaa, .b = bbbbbbbbbbbb, .c = ccccccccccccc, .d = dddddddddddd };"),
		in_fn("\tFoo f = {\n\t\t.a = aaaaaaaaaaa,\n\t\t.b = bbbbbbbbbbbb,\n\t\t.c = ccccccccccccc,\n\t\t.d = dddddddddddd\n\t};"), &c);
}

fn void macro_calls_and_calls_in_conditions_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	lists_check(in_fn("\t@foo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\t@foo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
	lists_check(in_fn("\treturn foo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\treturn foo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
}

fn void a_list_that_fits_stays_on_its_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	lists_check(in_fn("\tfoo(a, b, c);"), in_fn("\tfoo(a, b, c);"), &c);
	lists_check(in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, ddddddd);"), in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, ddddddd);"), &c);
	// reflow joins a break made by hand when the list fits
	c = lists_config("one_per_line", "reflow");
	lists_check(in_fn("\tfoo(a,\n\t\tb,\n\t\tc);"), in_fn("\tfoo(a, b, c);"), &c);
}

fn void only_the_lists_that_must_wrap_go_one_per_line() @test
{
	c3f::Config c = lists_config("one_per_line");
	// the inner call fits on its line: it stays whole while the outer list is stacked
	lists_check(in_fn("\tx = outer(inner(aaaaaaaaaaa, bbbbbbbbbbbb), ccccccccccccc, dddddddddddd, eeeeeeeeeee);"),
		in_fn("\tx = outer(\n\t\tinner(aaaaaaaaaaa, bbbbbbbbbbbb),\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee\n\t);"), &c);
	// both levels need it
	lists_check(in_fn("\tx = outer(inner(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd), eeeeeeeeeee, fffffffffff);"),
		in_fn("\tx = outer(\n\t\tinner(\n\t\t\taaaaaaaaaaa,\n\t\t\tbbbbbbbbbbbb,\n\t\t\tccccccccccccc,\n\t\t\tdddddddddddd\n\t\t),\n\t\teeeeeeeeeee,\n\t\tfffffffffff\n\t);"), &c);
}

fn void a_parenthesized_expression_or_a_loop_header_is_no_list() @test
{
	c3f::Config c = lists_config("one_per_line");
	lists_check(in_fn("\tfor (int i = 0, j = 1; i < aaaaaaaaaaaaaaaaaaaaaaaaaaa && j < bbbbbbbbbbbbbbbbbbbb; i++) x();"),
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
	lists_check(src, src, &c);
	c3f::Config n = c3f::defaults();
	(void)n.set("c3f_line_breaks", "wrap");
	(void)n.set("c3f_wrap_lists", "one_per_line");
	lists_check(src, src, &n);
}

fn void no_comma_is_added_or_removed() @test
{
	c3f::Config c = lists_config("one_per_line");
	String out = fmt_with(in_fn(CALL), &c);
	assert(!out.contains("eeeeeeeeeee,"));
	// a list that has a trailing comma keeps it (and one item per line, as before)
	String trailing = in_fn("\tfoo(aaaaaaaaaaa, bbbbbbbbbbbb, ccccccccccccc, dddddddddddd, eeeeeeeeeee,);");
	String want = in_fn("\tfoo(\n\t\taaaaaaaaaaa,\n\t\tbbbbbbbbbbbb,\n\t\tccccccccccccc,\n\t\tdddddddddddd,\n\t\teeeeeeeeeee,\n\t);");
	lists_check(trailing, want, &c);
	// also when it would fit (reflow lays a statement out again)
	c3f::Config r = lists_config("one_per_line", "reflow");
	lists_check(in_fn("\tfoo(a, b,);"), in_fn("\tfoo(\n\t\ta,\n\t\tb,\n\t);"), &r);
	// with the magic comma off the trailing comma is only a token
	(void)c.set("c3f_magic_comma", "false");
	lists_check(in_fn("\tfoo(a, b,);"), in_fn("\tfoo(a, b,);"), &c);
}

fn void one_per_line_output_is_stable_in_every_mode() @test
{
	String call = in_fn("\tx = aaaa(bbbbbbbbbbbbbbbb, cccccccccccccccccccccccccccccccc, dddddddddd(eeeeeeeeeeeeeeee, ffffffffffffffff, gggggggggggggggg, hhhhhhhhhhhhhh));");
	foreach (String breaks : { "wrap", "wrap_rewrite", "reflow" })
	{
		foreach (String cont : { "keep", "indent", "align" })
		{
			c3f::Config c = lists_config("one_per_line", breaks, "50");
			(void)c.set("c3f_continuation", cont);
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
	(void)c.set("c3f_wrap_lists", "ONE_PER_LINE");
	assert(c.wrap_lists == c3f::WrapLists.ONE_PER_LINE);
	assert(c.value_text(c3f::Key.WRAP_LISTS) == "one_per_line");
	assert(c3f::allowed_values(c3f::Key.WRAP_LISTS) == "fill, one_per_line");
}
