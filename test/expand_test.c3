module c3f_test;
import c3f;

<* Formats under `settings` (key, value, ...), requires a second run to change nothing, and returns the text. *>
fn String expanded(String src, String[] settings) @local
{
	c3f::Config cfg = c3f::defaults();
	(void)cfg.set("c3f_one_line_blocks", "expand");
	for (sz i = 0; i + 1 < settings.len; i += 2) (void)cfg.set(settings[i], settings[i + 1]);
	String once = fmt_with(src, &cfg);
	assert(fmt_with(once, &cfg) == once, "not idempotent:\n%s", once);
	return once;
}

fn void expanded_compile_time_branch_stays_inside_its_function() @test
{
	String src = "module t;\nfn void f7() { $if true: a(); $else b(); $endif }\n";
	String keep = expanded(src, {});
	assert(keep == "module t;\nfn void f7()\n{\n\t$if true:\n\ta();\n\t$else\n\tb();\n\t$endif\n}\n", "got:\n%s", keep);
	String indent = expanded(src, { "c3f_compile_time_indent", "indent" });
	assert(indent == "module t;\nfn void f7()\n{\n\t$if true:\n\t\ta();\n\t$else\n\t\tb();\n\t$endif\n}\n", "got:\n%s", indent);
	String flush = expanded(src, { "c3f_compile_time_indent", "flush" });
	assert(flush == keep, "got:\n%s", flush);
	// a directive written at column 0 in the source stays there under keep
	String col0 = expanded("module t;\nfn void g()\n{\n$if true:\n\ta();\n$endif\n}\n", {});
	assert(col0 == "module t;\nfn void g()\n{\n$if true:\n\ta();\n$endif\n}\n", "got:\n%s", col0);
}
