module c3f_test;
import c3f;

<* Formats under `settings` (key, value, ...), requires a second run to change nothing, and returns the text. *>
fn String spaced(String src, String[] settings) @local
{
	c3f::Config cfg = c3f::defaults();
	for (sz i = 0; i + 1 < settings.len; i += 2) (void)cfg.set(settings[i], settings[i + 1]);
	String once = fmt_with(src, &cfg);
	assert(fmt_with(once, &cfg) == once, "not idempotent:\n%s", once);
	return once;
}

fn void a_star_before_a_dereference_is_a_spaced_operator() @test
{
	String src = "module t;\nfn void f(int a, int b, int* p)\n{\n\tint c = a ** b;\n\tint d = a * *p;\n\tint e = a**b;\n\tint g = **p;\n}\n";
	foreach (style : (String[]){ "stdlib", "strict", "knr" })
	{
		String got = spaced(src, { "c3f_style", style });
		assert(got.contains("\tint c = a * *b;\n"), "got:\n%s", got);
		assert(got.contains("\tint d = a * *p;\n"), "got:\n%s", got);
		assert(got.contains("\tint e = a**b;\n"), "got:\n%s", got);
		assert(got.contains("\tint g = **p;\n"), "got:\n%s", got);
	}
}

fn void compile_time_operators_are_spaced_in_every_style() @test
{
	String src = "module t;\nmacro bool m($a, $b, $c)\n{\n\treturn $a&&&$b|||$c;\n}\nmacro m2($a, $b)\n{\n\treturn $a+++$b;\n}\n";
	foreach (style : (String[]){ "stdlib", "strict", "knr" })
	{
		String got = spaced(src, { "c3f_style", style });
		assert(got.contains("\treturn $a &&& $b ||| $c;\n"), "got:\n%s", got);
		assert(got.contains("\treturn $a +++ $b;\n"), "got:\n%s", got);
	}
}
