module c3f_test;
import c3f, std::io;

<* Formats under `settings` (key, value, ...); a second run must change nothing. Returns the first result. *>
fn String settle(String src, String[] settings) @local
{
	c3f::Config cfg = c3f::defaults();
	for (sz i = 0; i + 1 < settings.len; i += 2) (void)cfg.set(settings[i], settings[i + 1]);
	String once = fmt_with(src, &cfg);
	String twice = fmt_with(once, &cfg);
	assert(twice == once, "not idempotent:\n%s\n--- then ---\n%s", once, twice);
	return once;
}

fn void sorted_imports_with_no_blank_lines_allowed() @test
{
	String src = "module t;\nimport std::io;\n\nimport abc;\n\nfn void main() {}\n";
	String[] modes = { "lines", "all", "split", "lists" };
	foreach (mode : modes)
	{
		(void)settle(src, { "c3f_sort_imports", mode, "c3f_max_blank_lines", "0" });
		(void)settle(src, { "c3f_sort_imports", mode, "c3f_max_blank_lines", "1" });
	}
	// the runs that blank lines separated are one run once the blank lines are gone
	String got = settle(src, { "c3f_sort_imports", "all", "c3f_max_blank_lines", "0" });
	assert(got == "module t;\nimport abc;\nimport std::io;\nfn void main() {}\n", "got:\n%s", got);
	// with blank lines allowed the runs stay apart
	got = settle(src, { "c3f_sort_imports", "all", "c3f_max_blank_lines", "2" });
	assert(got == src, "got:\n%s", got);
	// a comment that a blank line kept away from its import moves with it once the blank line is gone
	got = settle("module t;\n// c\n\nimport z;\nimport a;\n\n// d\nimport y;\n", { "c3f_style", "strict", "c3f_max_blank_lines", "0" });
	assert(got == "module t;\nimport a;\n// d\nimport y;\n// c\nimport z;\n", "got:\n%s", got);
}

fn void expanded_lambda_in_an_initializer() @test
{
	// the lambda's body goes on lines of its own, so the initializer spans lines: its elements start on a line after the '{'
	String src = "module t;\nfn void f()\n{\n\tCb c = { fn () { io::printn(\"x\"); } };\n}\n";
	String got = settle(src, { "c3f_one_line_blocks", "expand" });
	assert(got == "module t;\nfn void f()\n{\n\tCb c = {\n\t\tfn () {\n\t\t\tio::printn(\"x\");\n\t\t} };\n}\n", "got:\n%s", got);
	// an initializer inside another one
	(void)settle("fn void f()\n{\n\tCb c = { { fn () { a(); b(); } }, { 1, 2 } };\n}\n", { "c3f_one_line_blocks", "expand" });
	// one on a line stays as it is
	got = settle("fn void f()\n{\n\tint[] a = { 1, 2 };\n}\n", { "c3f_one_line_blocks", "expand" });
	assert(got == "fn void f()\n{\n\tint[] a = { 1, 2 };\n}\n", "got:\n%s", got);
}

fn void braces_under_compile_time_branches_with_knr_braces() @test
{
	// `$if X:` and `$else` are treated alike: the brace goes to the end of the header line
	String src = "macro f()\n{\n\t$if X:\n\t\t{\n\t\t\ta();\n\t\t}\n\t$else\n\t\t{\n\t\t\tb();\n\t\t}\n\t$endif\n}\n";
	String got = settle(src, { "c3f_style", "knr" });
	assert(got == "macro f() {\n\t$if X: {\n\t\ta();\n\t}\n\t$else {\n\t\tb();\n\t}\n\t$endif\n}\n", "got:\n%s", got);
	got = settle(src, { "c3f_brace_style", "linux" });
	assert(got == "macro f()\n{\n\t$if X: {\n\t\ta();\n\t}\n\t$else {\n\t\tb();\n\t}\n\t$endif\n}\n", "got:\n%s", got);
	// with Allman braces a `$else {` stays as written, on the line or below it
	String joined = "fn void f()\n{\n\t$if X: a(); $else {\n\t\tb();\n\t}\n\t$endif\n}\n";
	got = settle(joined, {});
	assert(got == joined, "got:\n%s", got);
	String below = "fn void f()\n{\n\t$if X: a();\n\t$else\n\t{\n\t\tb();\n\t}\n\t$endif\n}\n";
	got = settle(below, {});
	assert(got == below, "got:\n%s", got);
	// with Allman braces they stay on their own lines
	(void)settle(src, {});
	// blocks on one line are left as they are
	String one = "macro f()\n{\n\t$if Y: { c(); } $else { d(); } $endif\n}\n";
	got = settle(one, { "c3f_style", "knr" });
	assert(got == "macro f() {\n\t$if Y: { c(); } $else { d(); } $endif\n}\n", "got:\n%s", got);
}

fn void aligned_names_and_comments_settle_in_one_run() @test
{
	// a name column is not widened past the limit, but the limit is judged on the lines as they will be written
	String src = "struct GeneratorState {\n    GeneratorStateType state;\n"
		"    void* func;               // CompiledFunction*, opaque to avoid a circular dependency\n"
		"    void* func_obj;           // HObject* of the generator function itself, opaque.\n}\n";
	String got = settle(src, { "c3f_align", "decls", "c3f_align_comments", "always", "max_line_length", "100" });
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
				String got = settle(src, { style, kind, "c3f_line_breaks", mode, "max_line_length", width, "c3f_one_line_blocks", "expand" });
				// the header with the initializer stays on one line
				assert(got.contains("@tree((Column) { .gap = 4 }) {\n"), "got:\n%s", got);
			}
		}
	}
	// a header without an initializer is still wrapped
	String got = settle("module m;\nfn void g()\n{\n\tif (aaaaaaaaaaaaaaaaaaa && bbbbbbbbbbbbbbbbbbbbbb && cccccccccccccc) {\n\t\ty();\n\t}\n}\n",
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
				(void)settle(src, { "indent_style", "space", "indent_size", size, "tab_width", tw, "c3f_continuation", cont });
			}
		}
	}
	String got = settle(src, { "indent_style", "space", "indent_size", "4", "tab_width", "8" });
	assert(got == "enum E : uint (uint w, ulong[2] i)\n{\n    S { 512,\n        {\n            0x1,\n            0x2\n        }\n    },\n}\n", "got:\n%s", got);
}
