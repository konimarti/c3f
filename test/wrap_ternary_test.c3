module c3f_test;
import c3f, std::io;

fn void ternaries_wrap_at_their_question_mark_and_colon() @test
{
	String[] modes = { "wrap", "reflow" };
	foreach (mode : modes)
	{
		c3f::Config cfg = c3f::defaults();
		(void)cfg.set("max_line_length", "80");
		(void)cfg.set("c3f_line_breaks", mode);
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
			(void)cfg.set("max_line_length", w);
			(void)cfg.set("c3f_line_breaks", mode);
			String once = fmt_with(src, &cfg);
			assert(fmt_with(once, &cfg) == once, "not idempotent at %s:\n%s", w, once);
			String a = src.treplace("\n", "").treplace("\t", "").treplace(" ", "");
			String b = once.treplace("\n", "").treplace("\t", "").treplace(" ", "");
			assert(a == b, "tokens changed:\n%s", once);
		}
	}
}
