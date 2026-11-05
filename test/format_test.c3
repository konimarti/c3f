module c3f_test;
import c3f, std::io;

<* Tests run inside the runner's temporary scope; tmem results live until the test ends. *>
fn String fmt_with(String src, c3f::Config* cfg)
{
	c3f::FormatResult r = c3f::format(tmem, src, cfg);
	return r.text;
}

<* Formats `src`, compares with `want`, and checks that formatting again changes nothing. *>
fn void check(String src, String want, c3f::Config* cfg = null) @local
{
	c3f::Config d = c3f::defaults();
	if (!cfg) cfg = &d;
	String got = fmt_with(src, cfg);
	if (got != want) io::eprintfn("--- want ---\n%s--- got ---\n%s---", want, got);
	assert(got == want);
	String again = fmt_with(got, cfg);
	if (again != got) io::eprintfn("--- not idempotent ---\n%s---", again);
	assert(again == got);
}

fn void spacing() @test
{
	check("fn void f()\n{\n\tint a=b+c*2;\n\tfoo( a ,b );\n}\n",
	      "fn void f()\n{\n\tint a = b + c * 2;\n\tfoo(a, b);\n}\n");
	check("fn void f()\n{\n\tif(x) return;\n\twhile(y) y--;\n}\n",
	      "fn void f()\n{\n\tif (x) return;\n\twhile (y) y--;\n}\n");
	check("fn void f()\n{\n\tx = -1;\n\ty = a - b;\n\tz = *p;\n\tw = (int)v;\n}\n",
	      "fn void f()\n{\n\tx = -1;\n\ty = a - b;\n\tz = *p;\n\tw = (int)v;\n}\n");
}

fn void indentation() @test
{
	check("fn void f()\n{\n        int x;\n  if (x)\n  {\n  return;\n  }\n}\n",
	      "fn void f()\n{\n\tint x;\n\tif (x)\n\t{\n\t\treturn;\n\t}\n}\n");
	check("struct Foo\n{\nint a;\n    int b;\n}\n", "struct Foo\n{\n\tint a;\n\tint b;\n}\n");
	check("enum Color\n{\nRED,\n  GREEN,\n}\n", "enum Color\n{\n\tRED,\n\tGREEN,\n}\n");
}

fn void continuation_lines_keep_their_extra_indent() @test
{
	check("fn void f()\n{\n    foo(a,\n        b);\n}\n", "fn void f()\n{\n\tfoo(a,\n\t\tb);\n}\n");
	check("fn void f()\n{\n\tfoo(a,\n\t    b);\n}\n", "fn void f()\n{\n\tfoo(a,\n\t    b);\n}\n");
}

fn void switch_and_case() @test
{
	check("fn void f()\n{\nswitch (x)\n{\ncase 1:\nfoo();\ndefault:\nbar();\n}\n}\n",
	      "fn void f()\n{\n\tswitch (x)\n\t{\n\t\tcase 1:\n\t\t\tfoo();\n\t\tdefault:\n\t\t\tbar();\n\t}\n}\n");
	check("fn void f()\n{\n\tswitch (x)\n\t{\n\t\tcase 1:\n\t\t{\n\t\t\tfoo();\n\t\t}\n\t}\n}\n",
	      "fn void f()\n{\n\tswitch (x)\n\t{\n\t\tcase 1:\n\t\t{\n\t\t\tfoo();\n\t\t}\n\t}\n}\n");
}

fn void compile_time_blocks() @test
{
	check("fn void f()\n{\n\t$if FOO:\n\t\tbar();\n\t$else\n\t\tbaz();\n\t$endif\n}\n",
	      "fn void f()\n{\n\t$if FOO:\n\t\tbar();\n\t$else\n\t\tbaz();\n\t$endif\n}\n");
	check("fn void f()\n{\n\t$for var $i = 0; $i < 3; $i++:\n\t\tbar($i);\n\t$endfor\n}\n",
	      "fn void f()\n{\n\t$for var $i = 0; $i < 3; $i++:\n\t\tbar($i);\n\t$endfor\n}\n");
	// a directive at column 0 inside a block stays there and adds no level
	check("fn void f()\n{\n$if FOO:\n\tbar();\n$endif\n}\n", "fn void f()\n{\n$if FOO:\n\tbar();\n$endif\n}\n");
}

fn void braces() @test
{
	check("fn void f() {\n\tif (x) {\n\t\ty();\n\t} else {\n\t\tz();\n\t}\n}\n",
	      "fn void f()\n{\n\tif (x)\n\t{\n\t\ty();\n\t}\n\telse\n\t{\n\t\tz();\n\t}\n}\n");
	c3f::Config knr = c3f::defaults();
	(void)knr.set("c3f_style", "knr");
	check("fn void f()\n{\n\tif (x)\n\t{\n\t\ty();\n\t}\n\telse\n\t{\n\t\tz();\n\t}\n}\n",
	      "fn void f() {\n\tif (x) {\n\t\ty();\n\t} else {\n\t\tz();\n\t}\n}\n", &knr);
	// one-line blocks, initializers and lambdas stay as they are
	check("fn void f()\n{\n\tif (x) { return; }\n\tFoo a = {\n\t\t.x = 1,\n\t};\n}\n",
	      "fn void f()\n{\n\tif (x) { return; }\n\tFoo a = {\n\t\t.x = 1,\n\t};\n}\n");
}

fn void blank_lines() @test
{
	check("fn void f()\n{\n\n\tx();\n\n\n\n\ty();\n\n}\n", "fn void f()\n{\n\tx();\n\n\n\ty();\n}\n");
	check("\n\nmodule foo;   \n", "module foo;\n");
}

fn void comments_are_untouched() @test
{
	check("fn void f()\n{\n  // a comment\n\tx(); /* inline */   // trailing\n}\n",
	      "fn void f()\n{\n\t// a comment\n\tx(); /* inline */   // trailing\n}\n");
	// a contract's inner lines move with its first line
	check("struct S\n{\n    <*\n     doc\n    *>\n    int a;\n}\n", "struct S\n{\n\t<*\n\t doc\n\t*>\n\tint a;\n}\n");
}

fn void alignment_survives_reindentation() @test
{
	check("struct S\n{\n    int    a;   // one\n    double b;   // two\n}\n",
	      "struct S\n{\n\tint    a;   // one\n\tdouble b;   // two\n}\n");
	check("fn void f()\n{\n\tx    = 1;\n\tlong = 2;\n}\n", "fn void f()\n{\n\tx    = 1;\n\tlong = 2;\n}\n");
}

fn void off_regions() @test
{
	check("fn void f()\n{\n// c3f off\n  int   a=1;\n// c3f on\n  int b=2;\n}\n",
	      "fn void f()\n{\n\t// c3f off\n  int   a=1;\n// c3f on\n\tint b = 2;\n}\n");
}

fn void guards() @test
{
	// removing the space would make one token
	check("fn void f()\n{\n\tx = a - -b;\n\ty = - -z;\n}\n", "fn void f()\n{\n\tx = a - -b;\n\ty = - -z;\n}\n");
}

fn void damaged_code_is_kept() @test
{
	// the unclosed '(' keeps the rest of the file as written; the part before it is formatted
	check("fn void f()\n{\n    int a=1;\n    foo(  1,\n}\n", "fn void f()\n{\n\tint a = 1;\n\tfoo(  1,\n}\n");
}

fn void line_endings() @test
{
	check("fn void f()\r\n{\r\n  x();\r\n}\r\n", "fn void f()\r\n{\r\n\tx();\r\n}\r\n");
	c3f::Config lf = c3f::defaults();
	(void)lf.set("end_of_line", "lf");
	check("fn void f()\r\n{\r\n  x();\r\n}\r\n", "fn void f()\n{\n\tx();\n}\n", &lf);
}

fn void options() @test
{
	c3f::Config c = c3f::defaults();
	(void)c.set("indent_style", "space");
	(void)c.set("indent_size", "2");
	check("fn void f()\n{\n\tif (x)\n\t{\n\t\ty();\n\t}\n}\n", "fn void f()\n{\n  if (x)\n  {\n    y();\n  }\n}\n", &c);
	c = c3f::defaults();
	(void)c.set("c3f_space_after_cast", "true");
	check("fn void f()\n{\n\tw = (int)v;\n}\n", "fn void f()\n{\n\tw = (int) v;\n}\n", &c);
	c = c3f::defaults();
	(void)c.set("c3f_pointer_style", "type");
	check("fn void f(Foo *p)\n{\n\tBar *q = null;\n}\n", "fn void f(Foo* p)\n{\n\tBar* q = null;\n}\n", &c);
	c = c3f::defaults();
	(void)c.set("c3f_max_blank_lines", "1");
	check("module x;\n\n\n\nint y;\n", "module x;\n\nint y;\n", &c);
	c = c3f::defaults();
	(void)c.set("c3f_align", "off");
	check("int    a = 1;\n", "int a = 1;\n", &c);
}

fn void config_errors() @test
{
	c3f::Config c = c3f::defaults();
	assert(@catch(c.set("c3f_nonsense", "1")) == c3f::UNKNOWN_KEY);
	assert(@catch(c.set("c3f_brace_style", "sideways")) == c3f::BAD_VALUE);
	assert(@catch(c.set("tab_width", "0")) == c3f::BAD_VALUE);
	assert(@ok(c.set("max_line_length", "off")));
}

fn void glob() @test
{
	assert(c3f::glob_match("*.c3", "foo.c3"));
	assert(!c3f::glob_match("*.c3", "dir/foo.c3"));
	assert(c3f::glob_match("**.c3", "dir/foo.c3"));
	assert(c3f::glob_match("*.{c3,c3i}", "foo.c3i"));
	assert(c3f::glob_match("src/[ab]?.c3", "src/b1.c3"));
	assert(!c3f::glob_match("[!a]*", "abc"));
}

fn void diff() @test
{
	assert(c3f::unified_diff(tmem, "x", "a\nb\n", "a\nb\n") == "");
	assert(c3f::unified_diff(tmem, "x", "a\nb\nc\n", "a\nB\nc\n") == "--- a/x\n+++ b/x\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n");
}

fn void edits_and_ranges() @test
{
	c3f::Config c = c3f::defaults();
	String src = "fn void f()\n{\n  a=1;\n  b=2;\n}\n";
	c3f::FormatResult r = c3f::format(tmem, src, &c);
	// applying the edits gives the formatted text
	DString d;
	d.tinit();
	sz at = 0;
	foreach (e : c3f::edits(tmem, src, r.text))
	{
		d.append(src[at:e.start - at]);
		d.append(e.text);
		at = e.end;
	}
	d.append(src[at..]);
	assert(d.str_view() == r.text);
	// only the third line is formatted
	sz from = 14;
	sz to = 20;
	assert(c3f::format_range(tmem, src, from, to, &c) == "fn void f()\n{\n\ta = 1;\n  b=2;\n}\n");
}

fn void decl_alignment() @test
{
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_align", "decls");
	check("struct S\n{\n\tint a;\n\tdouble bb;\n}\n", "struct S\n{\n\tint    a;\n\tdouble bb;\n}\n", &c);
	check("fn void f()\n{\n\tx = 1;\n\tlonger = 2;\n}\n", "fn void f()\n{\n\tx      = 1;\n\tlonger = 2;\n}\n", &c);
}

fn void regressions() @test
{
	// function bodies after @inline, a generic signature or a user attribute are blocks
	check("fn void f() @inline {\n\tx();\n}\n", "fn void f() @inline\n{\n\tx();\n}\n");
	check("fn void f(Type x) <Type> {\n\tx();\n}\n", "fn void f(Type x) <Type>\n{\n\tx();\n}\n");
	// generic arguments with or without a space
	check("fn void f()\n{\n\tfoo {Type }(a);\n}\n", "fn void f()\n{\n\tfoo{Type}(a);\n}\n");
	// a comment after '{' still opens the block
	check("fn void f()\n{\nif (x) { // c\nfoo();\n}\n}\n", "fn void f()\n{\n\tif (x)\n\t{ // c\n\t\tfoo();\n\t}\n}\n");
	// tokens that merely share a column are not aligned
	check("fn int  foo() {\n return x;\n}\n", "fn int  foo()\n{\n\treturn x;\n}\n");
	// expanding one-line blocks also moves the else
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_one_line_blocks", "expand");
	check("fn void f()\n{\n\tif (c) { a(); } else { b(); }\n}\n",
	      "fn void f()\n{\n\tif (c)\n\t{\n\t\ta();\n\t}\n\telse\n\t{\n\t\tb();\n\t}\n}\n", &c);
	// indent_size = tab follows tab_width, whatever the order
	c = c3f::defaults();
	(void)c.set("indent_size", "tab");
	(void)c.set("tab_width", "8");
	c.finish();
	assert(c.indent_size == 8);
	// a missing final newline shows in the diff
	assert(c3f::unified_diff(tmem, "x", "a", "a\n") == "--- a/x\n+++ b/x\n@@ -1,1 +1,1 @@\n-a\n\\ No newline at end of file\n+a\n");
}

fn void more_regressions() @test
{
	// continuation lines of a compile-time header stay put
	check("fn void f()\n{\n\t$if $defined(a) ||| $defined(\n\t\tb):\n\t\tx();\n\t$endif\n}\n",
	      "fn void f()\n{\n\t$if $defined(a) ||| $defined(\n\t\tb):\n\t\tx();\n\t$endif\n}\n");
	// trailing comments on consecutive lines share a column
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_align_comments", "always");
	check("fn void f()\n{\n\tint a; // first\n\tint bbbbb; // second\n}\n", "fn void f()\n{\n\tint a;     // first\n\tint bbbbb; // second\n}\n", &c);
}

fn void linux_braces_trailing_comments_and_arrows() @test
{
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_brace_style", "linux");
	// function bodies on their own line, every other block K&R
	check("struct S\n{\n\tint a;\n}\nfn void f() {\n\tif (x)\n\t{\n\t\ty();\n\t}\n\telse\n\t{\n\t\tz();\n\t}\n}\n",
	      "struct S {\n\tint a;\n}\nfn void f()\n{\n\tif (x) {\n\t\ty();\n\t} else {\n\t\tz();\n\t}\n}\n", &c);
	c = c3f::defaults();
	(void)c.set("c3f_trailing_comment_spaces", "2");
	check("fn void f()\n{\n\ty(); // one\n\tz();    // two\n}\n", "fn void f()\n{\n\ty();  // one\n\tz();  // two\n}\n", &c);
	c = c3f::defaults();
	(void)c.set("c3f_align", "decls");
	check("fn int g() => 1;\nfn int longer_name() => 2;\n", "fn int g()           => 1;\nfn int longer_name() => 2;\n", &c);
}

fn void import_sorting() @test
{
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_sort_imports", "all");
	// runs are sorted on their own; comments and attributes move with their statement
	check("module x;\n// io\nimport std::io;\nimport std::collections::list, std::collections::map @public; // c\n\nimport zeta, alpha;\nimport beta;\n",
	      "module x;\nimport std::collections::list, std::collections::map @public; // c\n// io\nimport std::io;\n\nimport alpha, zeta;\nimport beta;\n", &c);
	assert(c3f::compare_paths("std::io", "std::io::file") < 0);
	assert(c3f::compare_paths("std::io::file", "std::math") < 0);
	assert(c3f::compare_paths("a", "a") == 0);
	c = c3f::defaults();
	check("module x;\nimport b;\nimport a;\n", "module x;\nimport b;\nimport a;\n", &c);   // off by default
}

fn void import_sorting_edge_cases() @test
{
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_sort_imports", "lines");
	// a range never reorders imports, and never loses one
	String src = "module foo;\nimport zzz;\nimport aaa;\nint  x;\n";
	assert(c3f::format_range(tmem, src, 0, 20, &c) == src);
	// only statements on lines of their own are sorted
	check("module x;\nimport ppp; /* c */ import ooo;\nimport bbb;\nimport aaa; // a\n",
	      "module x;\nimport ppp; /* c */ import ooo;\nimport aaa; // a\nimport bbb;\n", &c);
}

fn void wrapping() @test
{
	c3f::Config c = c3f::defaults();
	(void)c.set("max_line_length", "40");
	(void)c.set("c3f_line_breaks", "long");
	check("fn void f()\n{\n\tint r = compute(first_argument, second_argument);\n\tshort(a);\n}\n",
	      "fn void f()\n{\n\tint r = compute(first_argument,\n\t\tsecond_argument);\n\tshort(a);\n}\n", &c);
	(void)c.set("c3f_wrap_solver", "search");
	check("fn void f()\n{\n\tif (alpha_condition && beta_condition || gamma) return;\n}\n",
	      "fn void f()\n{\n\tif (alpha_condition\n\t\t&& beta_condition\n\t\t|| gamma) return;\n}\n", &c);
	// a wrapped initializer item stays where the next run puts it
	c = c3f::defaults();
	(void)c.set("max_line_length", "50");
	(void)c.set("c3f_line_breaks", "fit");
	check("fn void f()\n{\n\tFoo x = { .alpha = compute_value(1, 2), .beta = other_value(3) };\n}\n",
	      "fn void f()\n{\n\tFoo x = { .alpha = compute_value(1, 2),\n\t\t.beta = other_value(3) };\n}\n", &c);
}
