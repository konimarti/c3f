module c3f_test;
import c3f;

<* Formats under `settings` (key, value, ...) with the option that expands one-line blocks. *>
fn String expanded(String src, String[] settings) @local
{
	c3f::Config cfg = config_with(settings);
	assert(@ok(cfg.set("c3f_one_line_blocks", "expand")));
	return settled_cfg(src, &cfg);
}

fn void expanded_compile_time_branch_stays_inside_its_function() @test
{
	String src = "module t;\nfn void f7() { $if true: a(); $else b(); $endif }\n";
	String keep = expanded(src, { "c3f_compile_time_indent", "keep" });
	assert(keep == "module t;\nfn void f7()\n{\n\t$if true:\n\ta();\n\t$else\n\tb();\n\t$endif\n}\n", "got:\n%s", keep);
	String indent = expanded(src, { "c3f_compile_time_indent", "indent" });
	assert(indent == "module t;\nfn void f7()\n{\n\t$if true:\n\t\ta();\n\t$else\n\t\tb();\n\t$endif\n}\n", "got:\n%s", indent);
	String flush = expanded(src, { "c3f_compile_time_indent", "flush" });
	assert(flush == keep, "got:\n%s", flush);
	// a directive written at column 0 in the source stays there under keep
	String col0 = expanded("module t;\nfn void g()\n{\n$if true:\n\ta();\n$endif\n}\n", { "c3f_compile_time_indent", "keep" });
	assert(col0 == "module t;\nfn void g()\n{\n$if true:\n\ta();\n$endif\n}\n", "got:\n%s", col0);
}

fn void expanded_loop_before_a_while_loop_is_not_a_do_loop() @test
{
	String got = expanded("module t;\nfn void f(bool x)\n{\n\tfor (;;) { break; } while (x) { a(); }\n}\n", {});
	assert(got == "module t;\nfn void f(bool x)\n{\n\tfor (;;)\n\t{\n\t\tbreak;\n\t}\n\twhile (x)\n\t{\n\t\ta();\n\t}\n}\n", "got:\n%s", got);
	// the tail of a real do loop stays after its block
	got = expanded("module t;\nfn void f(bool x)\n{\n\tdo { a(); } while (x);\n}\n", {});
	assert(got == "module t;\nfn void f(bool x)\n{\n\tdo\n\t{\n\t\ta();\n\t} while (x);\n}\n", "got:\n%s", got);
}
