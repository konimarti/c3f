module c3f_test;
import c3f, std::io;

fn void sorted_imports_with_no_blank_lines_allowed() @test
{
	String src = "module t;\nimport std::io;\n\nimport abc;\n\nfn void main() {}\n";
	String[] modes = { "lines", "all", "split", "lists" };
	foreach (mode : modes)
	{
		(void)settled(src, { "c3f_sort_imports", mode, "c3f_max_blank_lines", "0" });
		(void)settled(src, { "c3f_sort_imports", mode, "c3f_max_blank_lines", "1" });
	}
	// the runs that blank lines separated are one run once the blank lines are gone
	String got = settled(src, { "c3f_sort_imports", "all", "c3f_max_blank_lines", "0" });
	assert(got == "module t;\nimport abc;\nimport std::io;\nfn void main() {}\n", "got:\n%s", got);
	// with blank lines allowed the runs stay apart
	got = settled(src, { "c3f_sort_imports", "all", "c3f_max_blank_lines", "2" });
	assert(got == src, "got:\n%s", got);
	// a comment that a blank line kept away from its import moves with it once the blank line is gone
	got = settled("module t;\n// c\n\nimport z;\nimport a;\n\n// d\nimport y;\n", { "c3f_style", "strict", "c3f_sort_imports", "all", "c3f_max_blank_lines", "0" });
	assert(got == "module t;\nimport a;\n// d\nimport y;\n// c\nimport z;\n", "got:\n%s", got);
}

fn void expanded_lambda_in_an_initializer() @test
{
	// the lambda's body goes on lines of its own, so the initializer spans lines: its elements start on a line after the '{'
	String src = "module t;\nfn void f()\n{\n\tCb c = { fn () { io::printn(\"x\"); } };\n}\n";
	String got = settled(src, { "c3f_one_line_blocks", "expand" });
	assert(got == "module t;\nfn void f()\n{\n\tCb c = {\n\t\tfn () {\n\t\t\tio::printn(\"x\");\n\t\t}\n\t};\n}\n", "got:\n%s", got);
	// an initializer inside another one
	(void)settled("fn void f()\n{\n\tCb c = { { fn () { a(); b(); } }, { 1, 2 } };\n}\n", { "c3f_one_line_blocks", "expand" });
	// one on a line stays as it is
	got = settled("fn void f()\n{\n\tint[] a = { 1, 2 };\n}\n", { "c3f_one_line_blocks", "expand" });
	assert(got == "fn void f()\n{\n\tint[] a = { 1, 2 };\n}\n", "got:\n%s", got);
}

fn void braces_under_compile_time_branches_with_knr_braces() @test
{
	// `$if X:` and `$else` are treated alike: the brace goes to the end of the header line
	String src = "macro f()\n{\n\t$if X:\n\t\t{\n\t\t\ta();\n\t\t}\n\t$else\n\t\t{\n\t\t\tb();\n\t\t}\n\t$endif\n}\n";
	String got = settled(src, { "c3f_style", "knr" });
	assert(got == "macro f() {\n\t$if X: {\n\t\ta();\n\t}\n\t$else {\n\t\tb();\n\t}\n\t$endif\n}\n", "got:\n%s", got);
	got = settled(src, { "c3f_brace_style", "linux" });
	assert(got == "macro f()\n{\n\t$if X: {\n\t\ta();\n\t}\n\t$else {\n\t\tb();\n\t}\n\t$endif\n}\n", "got:\n%s", got);
	// with Allman braces a `$else {` stays as written, on the line or below it
	// (the indentation of the bodies is kept here, so that only the braces are compared)
	String joined = "fn void f()\n{\n\t$if X: a(); $else {\n\t\tb();\n\t}\n\t$endif\n}\n";
	got = settled(joined, { "c3f_compile_time_indent", "keep", "c3f_compile_time_body", "keep" });
	assert(got == joined, "got:\n%s", got);
	String below = "fn void f()\n{\n\t$if X: a();\n\t$else\n\t{\n\t\tb();\n\t}\n\t$endif\n}\n";
	got = settled(below, { "c3f_compile_time_indent", "keep", "c3f_compile_time_body", "keep" });
	assert(got == below, "got:\n%s", got);
	// with Allman braces they stay on their own lines
	(void)settled(src, {});
	// blocks on one line are left as they are
	String one = "macro f()\n{\n\t$if Y: { c(); } $else { d(); } $endif\n}\n";
	got = settled(one, { "c3f_style", "knr" });
	assert(got == "macro f() {\n\t$if Y: { c(); } $else { d(); } $endif\n}\n", "got:\n%s", got);
}

fn void aligned_names_and_comments_settle_in_one_run() @test
{
	// a name column is not widened past the limit, but the limit is judged on the lines as they will be written
	String src = "struct GeneratorState {\n    GeneratorStateType state;\n"
		"    void* func;               // CompiledFunction*, opaque to avoid a circular dependency\n"
		"    void* func_obj;           // HObject* of the generator function itself, opaque.\n}\n";
	String got = settled(src, { "c3f_align", "decls", "c3f_align_comments", "always", "max_line_length", "100" });
	assert(got == "struct GeneratorState\n{\n\tGeneratorStateType state;\n"
		"\tvoid*              func;     // CompiledFunction*, opaque to avoid a circular dependency\n"
		"\tvoid*              func_obj; // HObject* of the generator function itself, opaque.\n}\n", "got:\n%s", got);
}

fn void header_with_an_initializer_under_expand() @test
{
	String src = "module m;\nfn Element* f(Ui* ui)\n{\n\treturn @subtree(ui)\n\t{\n"
		"\t\t@tree((Column) { .size = { 380, 0 }, .gap = ANIM_GAP })\n\t\t{\n\t\t\tif (count == 0)\n\t\t\t{\n\t\t\t\ta();\n\t\t\t}\n\t\t\telse\n\t\t\t{\n"
		"\t\t\t\t@tree((Scroll) { .size = { 0, list_h } })\n\t\t\t\t{\n\t\t\t\t\t@tree((Column) { .gap = 4 })\n\t\t\t\t\t{\n"
		"\t\t\t\t\t\tfor (usz i = 0; i < count; i++)\n\t\t\t\t\t\t{\n\t\t\t\t\t\t\t@node(x);\n\t\t\t\t\t\t}\n\t\t\t\t\t};\n\t\t\t\t};\n\t\t\t}\n\t\t};\n\t};\n}\n";
	foreach (style : (String[]){ "c3f_style", "c3f_brace_style" })
	{
		String kind = style == "c3f_style" ? "knr" : "linux";
		foreach (width : (String[]){ "40", "50", "60", "65", "70", "75" })
		{
			foreach (mode : (String[]){ "reflow", "wrap" })
			{
				String got = settled(src, { "c3f_style", "stdlib", style, kind, "c3f_line_breaks", mode, "max_line_length", width, "c3f_one_line_blocks", "expand" });
				// the header with the initializer stays on one line
				assert(got.contains("@tree((Column) { .gap = 4 }) {\n"), "got:\n%s", got);
			}
		}
	}
	// a header without an initializer is still wrapped
	String got = settled("module m;\nfn void g()\n{\n\tif (aaaaaaaaaaaaaaaaaaa && bbbbbbbbbbbbbbbbbbbbbb && cccccccccccccc) {\n\t\ty();\n\t}\n}\n",
		{ "c3f_style", "knr", "c3f_line_breaks", "wrap", "max_line_length", "40", "c3f_one_line_blocks", "expand" });
	assert(got.contains("\t\t&& bbbbbbbbbbbbbbbbbbbbbb"), "got:\n%s", got);
}

fn void spaces_with_a_wider_tab_settle_in_one_run() @test
{
	// continuation lines written with tabs, under a nested initializer, formatted to spaces
	String src = "enum E : uint (uint w, ulong[2] i)\n{\n\tS { 512,\n\t\t{\n\t\t\t0x1,\n\t\t\t0x2\n\t\t}\n\t},\n}\n";
	foreach (tw : (String[]){ "2", "4", "8", "16" })
	{
		foreach (size : (String[]){ "2", "4", "8", "tab" })
		{
			foreach (cont : (String[]){ "keep", "indent", "align" })
			{
				(void)settled(src, { "c3f_style", "stdlib", "indent_style", "space", "indent_size", size, "tab_width", tw, "c3f_continuation", cont });
			}
		}
	}
	String got = settled(src, { "c3f_style", "stdlib", "indent_style", "space", "indent_size", "4", "tab_width", "8" });
	assert(got == "enum E : uint (uint w, ulong[2] i)\n{\n    S { 512,\n        {\n            0x1,\n            0x2\n        }\n    },\n}\n", "got:\n%s", got);
}

<* Tricky snippets: layouts, wrappings, alignments and sortings that once changed on a second run. *>
const String[*] SNIPPETS = {
	"fn void f(int a,\n\t\tint b) {\n\tx();\n}\nfn void g()\n{\n\tif (a &&\n\t\t\tb) {\n\t\ty();\n\t}\n}\n",
	"fn int compute_value_of_things(int first_argument, int second_argument, int third_argument, int fourth) {\n\treturn 1;\n}\n",
	"fn void g()\n{\n\tif (first_argument > second_argument && third_argument < fourth || some_flag_variable && another_flag) {\n\t\ty();\n\t}\n}\n",
	"fn int f()\n{\n\treturn condition_one_is_true_here ? some_value_when_true_expression : some_other_value_when_false;\n}\n",
	"fn int g(int c)\n{\n\tint result_value = condition_flag_variable ? first_alternative_value_name : second_alternative_value_nm;\n\treturn result_value;\n}\n",
	"module t;\nimport std::io;\n\nimport abc;\n\nfn void main() {}\n",
	"module t;\nfn void f()\n{\n\tCb c = { fn () { io::printn(\"x\"); } };\n}\n",
	"macro f()\n{\n\t$if X:\n\t\t{\n\t\t\ta();\n\t\t}\n\t$else\n\t\t{\n\t\t\tb();\n\t\t}\n\t$endif\n}\n",
	"struct GeneratorState {\n    GeneratorStateType state;\n    void* func;               // CompiledFunction*, opaque to avoid a circular dependency\n    void* func_obj;           // HObject* of the generator function itself, opaque.\n}\n",
	"module t;\nfn void f7() { $if true: a(); $else b(); $endif }\n",
	"module t;\nfn void f(bool x)\n{\n\tfor (;;) { break; } while (x) { a(); }\n}\n",
	"fn void f()\n{\n\tx = a[ 1 ];\n\ty = c[ i ];\n\tint[2][2] m = {{1,2},{3,4}};\n\tz = b[2];\n}\n",
	"module t;\nconst int K = 1;\nconst int L = 2;\nfn void a() {}\n\n\n\nfn void b() {}\nfn void c();\nfn void d()\n{\n}\nfn void e();\n",
	"module t;\nfn void f()\n{\n\t$if FOO:\n\t{\n\t\ta();\n\t}\n\t$else\n\t{\n\t\tb();\n\t}\n\t$endif\n}\n",
	"module t;\nfn void f(int x)\n{\n\tswitch (x)\n\t{\n\t\tcase 1:\n\t\t{\n\t\t\ta();\n\t\t}\n\t\tdefault:\n\t\t\tb();\n\t}\n}\n",
	"module t;\n// c\n\nimport z;\nimport a;\n\n// d\nimport y;\nimport std::io, std::core;\n\nfn void main() {}\n",
	"fn void f(int a,\n\t\tint b) {\n\tx();\n}\nfn void g()\n{\n\tif (a &&\n\t\t\tb) {\n\t\ty();\n\t} else if (c &&\n\t\t\td) {\n\t\tz();\n\t}\n}\n",
	"fn void f()\n{\n\tfoo(a,\n\t\tfn void() {\n\t\t\tx();\n\t\t}, b);\n\tfoo(fn void(int q) {\n\t\ty();\n\t});\n}\n",
	"fn int f(int c)\n{\n\tx = a_condition ? first_option_value_here_long : b_condition ? second_option_value_here_long : third_option_value_long;\n\treturn first_condition_expression && second_condition_expression ? the_true_value_expression_long : the_false_value;\n\tfoo(condition_one_is_true_here ? some_value_when_true_expression : some_other_value_when_false, 1, 2);\n}\n",
	"struct S\n{\n\tint a;        // first\n\tdouble bbbbb; // second\n\tchar* c;   /* third */\n\tFoo* next;\n\tvoid* func;               // CompiledFunction*, opaque to avoid a circular dependency\n\tvoid* func_obj;           // HObject* of the generator function itself, opaque.\n}\n",
	"macro f()\n{\n\t$if X:\n\t\t{\n\t\t\ta();\n\t\t}\n\t$else\n\t\t{\n\t\t\tb();\n\t\t}\n\t$endif\n}\n",
	"fn void f()\n{\n\tBaz b = { fn () { puts(\"Hello, World!\"); } };\n\tCb c = { { fn () { a(); b(); } }, { 1, 2 } };\n}\n",
};

<* The option sets of the idempotence sweep: key, value pairs applied in order. `check_tokens` is false where an option adds or moves tokens (import sorting, wrap_rewrite). *>
struct OptionSet @local
{
	String   name;
	String[] settings;
	bool     check_tokens;
}

const OptionSet[*] OPTION_SETS = {
	{ "default", {}, true },
	{ "strict", { "c3f_style", "strict" }, false },
	{ "knr", { "c3f_style", "knr" }, true },
	{ "wrap80", { "max_line_length", "80", "c3f_line_breaks", "wrap" }, true },
	{ "reflow80", { "c3f_style", "strict", "max_line_length", "80", "c3f_line_breaks", "reflow" }, false },
	{ "reflow60 one per line", { "max_line_length", "60", "c3f_line_breaks", "reflow", "c3f_wrap_lists", "one_per_line" }, true },
	{ "rewrite80", { "max_line_length", "80", "c3f_line_breaks", "wrap_rewrite" }, false },
	{ "align", { "c3f_align", "decls", "c3f_align_comments", "always", "max_line_length", "100" }, true },
	{ "align off", { "c3f_align", "off", "c3f_align_comments", "off", "c3f_trailing_comment_spaces", "1" }, true },
	{ "expand", { "c3f_one_line_blocks", "expand", "c3f_brace_style", "linux", "c3f_else_style", "own_line", "c3f_while_style", "same_line" }, true },
	{ "continuation", { "c3f_continuation", "align", "c3f_compile_time_indent", "indent", "c3f_case_indent", "flush", "indent_style", "space", "indent_size", "2" }, true },
	{ "continuation indent", { "c3f_continuation", "indent", "c3f_compile_time_indent", "flush", "c3f_space_after_cast", "true", "c3f_space_inside_brackets", "true", "c3f_space_inside_braces", "true", "c3f_pointer_style", "name" }, true },
	{ "sorted imports, no blank lines", { "c3f_sort_imports", "split", "c3f_top_level_decls", "blank", "c3f_max_blank_lines", "0", "c3f_trim_block_blanks", "false", "end_of_line", "crlf" }, false },
	{ "knr wrap", { "c3f_style", "knr", "max_line_length", "80", "c3f_line_breaks", "wrap" }, true },
	{ "linux reflow", { "c3f_brace_style", "linux", "max_line_length", "70", "c3f_line_breaks", "reflow", "c3f_continuation", "indent" }, true },
	{ "knr, tabs as 8, spaces", { "c3f_style", "knr", "indent_style", "space", "tab_width", "8", "c3f_continuation", "indent" }, true },
	{ "strict without sorting, wrapped", { "c3f_style", "strict", "c3f_sort_imports", "off", "max_line_length", "80", "c3f_line_breaks", "wrap" }, true },
};

<* The text without any whitespace: formatting that only moves whitespace leaves it unchanged. *>
fn String squeeze(String s) @local
{
	DString d;
	d.tinit();
	foreach (c : s) if (c != ' ' && c != '\t' && c != '\n' && c != '\r') d.append_char(c);
	return d.str_view();
}

fn void a_second_run_changes_nothing() @test
{
	DString failures;
	failures.tinit();
	foreach (set : OPTION_SETS)
	{
		Config cfg = c3f::defaults();
		for (sz i = 0; i + 1 < set.settings.len; i += 2) assert(@ok(cfg.set(set.settings[i], set.settings[i + 1])), "%s: %s", set.name, set.settings[i]);
		foreach (k, src : SNIPPETS)
		{
			String once = fmt_with(src, &cfg);
			String twice = fmt_with(once, &cfg);
			if (twice != once) failures.appendf("[%s] snippet %d is not stable\n", set.name, k);
			if (set.check_tokens && squeeze(once) != squeeze(src)) failures.appendf("[%s] snippet %d changed tokens\n", set.name, k);
		}
	}
	assert(failures.len() == 0, "\n%s", failures.str_view());
}
