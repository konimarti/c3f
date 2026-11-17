module c3f_test;
import c3f;

fn void a_star_before_a_dereference_is_a_spaced_operator() @test
{
	String src = "module t;\nfn void f(int a, int b, int* p)\n{\n\tint c = a ** b;\n\tint d = a * *p;\n\tint e = a**b;\n\tint g = **p;\n}\n";
	foreach (style : (String[]){ "stdlib", "strict", "knr" })
	{
		String got = settled(src, { "c3f_style", style });
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
		String got = settled(src, { "c3f_style", style });
		assert(got.contains("\treturn $a &&& $b ||| $c;\n"), "got:\n%s", got);
		assert(got.contains("\treturn $a +++ $b;\n"), "got:\n%s", got);
	}
}
