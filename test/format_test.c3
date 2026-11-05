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
	// and says so: the note names the line of the bracket
	c3f::Config d = c3f::defaults();
	c3f::FormatResult r = c3f::format(tmem, "fn void f()\n{\n\tfoo(1,\n}\nfn void g() {}\n", &d);
	assert(r.fallback);
	assert(r.notes.len() == 1 && r.notes[0].line == 3);
	r = c3f::format(tmem, "fn void f()\n{\n\tfoo(1);\n}\n", &d);
	assert(!r.fallback);
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
	assert(c3f::glob_match("{src,test}/**/*.{c3,c3i}", "test/a/b.c3i"));
	assert(!c3f::glob_match("{src,test}/*.c3", "lib/a.c3"));
	assert(c3f::glob_match("a\\*b", "a*b") && !c3f::glob_match("a\\*b", "axb"));
	// many stars against a long name that does not match: no exponential backtracking
	assert(!c3f::glob_match("*a*a*a*a*a*a*a*a*a*a*a*a*b", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"));
}

fn void paths() @test
{
	// POSIX and Windows paths, for the .editorconfig and git searches
	assert(c3f::absolute("/x/./y/../z.c3") == "/x/z.c3");
	assert(c3f::absolute("C:\\a\\b\\..\\c.c3") == "C:/a/c.c3");
	assert(c3f::parent_dir("/x/y") == "/x" && c3f::parent_dir("/x") == "/" && c3f::parent_dir("/") == "/");
	assert(c3f::parent_dir("C:/a/b") == "C:/a" && c3f::parent_dir("C:/a") == "C:/" && c3f::parent_dir("C:/") == "C:/");
	assert(c3f::is_root("/") && c3f::is_root("C:/") && !c3f::is_root("C:/a"));
	assert(c3f::join_path("C:/", ".git") == "C:/.git" && c3f::join_path("/x", ".git") == "/x/.git");
}

fn void diff() @test
{
	assert(c3f::unified_diff(tmem, "x", "a\nb\n", "a\nb\n") == "");
	assert(c3f::unified_diff(tmem, "x", "a\nb\nc\n", "a\nB\nc\n") == "--- a/x\n+++ b/x\n@@ -1,3 +1,3 @@\n a\n-b\n+B\n c\n");
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

fn void ternary_and_slice_colons() @test
{
	// a ternary's ':' is spaced in every mode; labels, named arguments and slices are not ternaries
	String src = "fn void f()\n{\n\tx = a ? x.y: e;\n\ty = foo(n: 1);\n\tswitch (q)\n\t{\n\t\tcase 1: w = t ? (b ? c : d) : z;\n\t}\n\tv = s[1 : 2];\n}\n";
	check(src, "fn void f()\n{\n\tx = a ? x.y : e;\n\ty = foo(n: 1);\n\tswitch (q)\n\t{\n\t\tcase 1: w = t ? (b ? c : d) : z;\n\t}\n\tv = s[1 : 2];\n}\n");
	// strict also makes slices tight
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_style", "strict");
	check(src, "fn void f()\n{\n\tx = a ? x.y : e;\n\ty = foo(n: 1);\n\tswitch (q)\n\t{\n\t\tcase 1: w = t ? (b ? c : d) : z;\n\t}\n\tv = s[1:2];\n}\n", &c);
}

fn void strict_mode() @test
{
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_style", "strict");
	// a statement after a control header, `$assert`'s message, pointers before a type name,
	// generic arguments (also as a return type), one-line bodies
	check("fn List{ int } f()\n{\n\tforeach (&o : x) *o = 1;\n\tif (a)(void)b;\n\t$assert X: \"m\";\n}\nfn Tok *Fmt.tok(&self) => null;\nstruct G {int a; }\n",
	      "fn List{int} f()\n{\n\tforeach (&o : x) *o = 1;\n\tif (a) (void)b;\n\t$assert X : \"m\";\n}\nfn Tok* Fmt.tok(&self) => null;\nstruct G { int a; }\n", &c);
}

fn void style_sweep_regressions() @test
{
	// the inside of a one-line block or initializer is padded alike on both ends
	check("fn void f() {int a=1; }\nfn void g() { int a;}\nfn void h() {int a;}\nint[2] x = { 1, 2};\n",
	      "fn void f() { int a = 1; }\nfn void g() { int a; }\nfn void h() {int a;}\nint[2] x = { 1, 2 };\n");
	// in every style: label and header colons are tight, prefix operators open statements
	// after blocks, comments and `$endif`
	String src = "fn void f()\n{\n\tswitch (x)\n\t{\n\t\tcase a.b :\n\t\t\tbreak;\n\t}\n\t$if X :\n\t\ty();\n\t$endif\n\t*p = 1;\n\tif (q)\n\t{\n\t\tz();\n\t}\n\t/* c */\n\t*s = 2;\n}\n";
	String want = "fn void f()\n{\n\tswitch (x)\n\t{\n\t\tcase a.b:\n\t\t\tbreak;\n\t}\n\t$if X:\n\t\ty();\n\t$endif\n\t*p = 1;\n\tif (q)\n\t{\n\t\tz();\n\t}\n\t/* c */\n\t*s = 2;\n}\n";
	check(src, want);
	c3f::Config c = c3f::defaults();
	(void)c.set("c3f_style", "strict");
	check(src, want, &c);
	// strict: a tie in a narrow context falls back to the broader one; function types are tight
	check("fn void f()\n{\n\tvar $r = $$h(@sprintf(\"%s\", $x, $i));\n}\nalias P = fn Eb (int a);\n",
	      "fn void f()\n{\n\tvar $r = $$h(@sprintf(\"%s\", $x, $i));\n}\nalias P = fn Eb(int a);\n", &c);
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
	check("fn void f()\n{\n\tif (alpha_condition && beta_condition || gamma) return;\n}\n",
	      "fn void f()\n{\n\tif (alpha_condition\n\t\t&& beta_condition\n\t\t|| gamma) return;\n}\n", &c);
	// a wrapped initializer item stays where the next run puts it
	c = c3f::defaults();
	(void)c.set("max_line_length", "50");
	(void)c.set("c3f_line_breaks", "fit");
	check("fn void f()\n{\n\tFoo x = { .alpha = compute_value(1, 2), .beta = other_value(3) };\n}\n",
	      "fn void f()\n{\n\tFoo x = { .alpha = compute_value(1, 2),\n\t\t.beta = other_value(3) };\n}\n", &c);
	// the arguments see the text glued after them; a macro call breaks like a call, an attribute stays whole
	c = c3f::defaults();
	(void)c.set("max_line_length", "60");
	(void)c.set("c3f_line_breaks", "long");
	check("fn void f()\n{\n\tif (spawn_actions(&actions, stdoutfd[1], libc::STDOUT_FD)) return FAILED_TO_OPEN~;\n"
	      "\treturn @atomic_exchange(ptr, value, AtomicOrdering.RELAXED, $alignment);\n}\n"
	      "extern fn int get_path(WString name, ulong len, Char16* buffer) @cname(\"GetPath\");\n",
	      "fn void f()\n{\n\tif (spawn_actions(&actions, stdoutfd[1],\n\t\tlibc::STDOUT_FD)) return FAILED_TO_OPEN~;\n"
	      "\treturn @atomic_exchange(ptr, value,\n\t\tAtomicOrdering.RELAXED, $alignment);\n}\n"
	      "extern fn int get_path(WString name, ulong len,\n\tChar16* buffer) @cname(\"GetPath\");\n", &c);
}

fn void release_review_regressions() @test
{
	c3f::Config d = c3f::defaults();
	c3f::Config strict = c3f::defaults();
	(void)strict.set("c3f_style", "strict");
	// a ternary '?' after ']' is spaced like any other (not the '?' of `int[]?`)
	check("fn void f()\n{\n\tx = a[i]?b:c;\n\tint[]? z = g();\n}\n", "fn void f()\n{\n\tx = a[i] ? b : c;\n\tint[]? z = g();\n}\n", &strict);
	// ... and the '?' of an optional return type stays tight, whatever follows in the file
	check("fn sz? Foo.peek(&self)\n{\n\treturn 0;\n}\nfn void g()\n{\n\tx = c ? a : b;\n}\n",
	      "fn sz? Foo.peek(&self)\n{\n\treturn 0;\n}\nfn void g()\n{\n\tx = c ? a : b;\n}\n", &strict);
	// the statement after a control header starts on the header's line, also when wrapping
	c3f::Config w = c3f::defaults();
	(void)w.set("max_line_length", "60");
	(void)w.set("c3f_line_breaks", "long");
	String src = "fn void f()\n{\n\tif (s - buf == 1 && (y || p > 0 || flags_hash_value)) *s++ = 1;\n}\n";
	check(src, "fn void f()\n{\n\tif (s - buf == 1\n\t\t&& (y || p > 0 || flags_hash_value)) *s++ = 1;\n}\n", &w);
	// a '\r' that c3c would drop keeps the whole file
	c3f::FormatResult r = c3f::format(tmem, "fn void f(){int x = 1; // c\rx = 2;}\n", &d);
	assert(r.fallback && !r.changed && r.notes.len() == 1);
	// notes are made once, about the input, even when wrapping runs again
	r = c3f::format(tmem, "fn void f()\n{\n\tint x = (1;\n}\n", &w);
	assert(r.fallback && r.notes.len() == 1 && r.notes[0].line == 3);
	// a stray closer keeps only the span around it
	check("fn void f()\n{\n\tint x = 3 ];\n}\nfn void g(){int z=3;}\n", "fn void f()\n{\n\tint x = 3 ];\n}\nfn void g() {int z = 3;}\n");
	// a binary operator that starts a wrapped line keeps its space: `* b` is no `*p`
	check("fn void f()\n{\n\tx = a\n\t\t*b;\n\t*p = 1;\n}\n", "fn void f()\n{\n\tx = a\n\t\t* b;\n\t*p = 1;\n}\n");
	// control headers are spaced in every style, as the stdlib writes them
	check("fn void f()\n{\n\tforeach(i,p:list) x();\n\tforeach_r(p:list) x();\n\tif(a) b();\n}\n",
	      "fn void f()\n{\n\tforeach (i, p : list) x();\n\tforeach_r (p : list) x();\n\tif (a) b();\n}\n");
	// a rejected value leaves the option as it was
	c3f::Config c = c3f::defaults();
	assert(@catch(c.set("tab_width", "0")));
	assert(@catch(c.set("indent_size", "99")));
	assert(c.tab_width == d.tab_width && c.indent_size == d.indent_size);
	// a comment above an import list does not stop the list from being sorted
	c3f::Config l = c3f::defaults();
	(void)l.set("c3f_sort_imports", "lists");
	check("module t;\n// c\nimport std::z, std::y;\n", "module t;\n// c\nimport std::y, std::z;\n", &l);
}

<* Formatting the result again changes nothing (for broken input, where the result itself is not the point). *>
fn void stable(String src, String key = "", String value = "") @local
{
	c3f::Config cfg = c3f::defaults();
	if (key.len) (void)cfg.set(key, value);
	String once = fmt_with(src, &cfg);
	String twice = fmt_with(once, &cfg);
	if (twice != once) io::eprintfn("--- not idempotent ---\n%s\n--- then ---\n%s\n---", once, twice);
	assert(twice == once);
}

fn void quality_review_regressions() @test
{
	c3f::Config d = c3f::defaults();
	c3f::Config knr = c3f::defaults();
	(void)knr.set("c3f_style", "knr");
	c3f::Config expand = c3f::defaults();
	(void)expand.set("c3f_one_line_blocks", "expand");
	// ternaries are paired like brackets: a '?' inside generic arguments or before an initializer
	check("fn void f()\n{\n\tList{int?} z = c?List{int?}{}:w;\n}\n", "fn void f()\n{\n\tList{int?} z = c ? List{int?}{} : w;\n}\n");
	// the ':' of `$assert`, also after a ternary, and an optional type before it stays tight
	check("fn int? f() {}\n$assert a ? b : c:\"m\";\n$assert x:\"m\";\n", "fn int? f() {}\n$assert a ? b : c : \"m\";\n$assert x : \"m\";\n");
	// `(Type){ … }` is a value, not a block: it is not expanded, and a block brace gets its space
	check("fn void f()\n{\n\ty = a * (int[<2>]){ 1, 2 };\n}\n", "fn void f()\n{\n\ty = a * (int[<2>]){ 1, 2 };\n}\n", &expand);
	check("fn void f() {\n\twhile (i < mid){\n\t\ti++;\n\t}\n}\n", "fn void f() {\n\twhile (i < mid) {\n\t\ti++;\n\t}\n}\n", &knr);
	// broken code (as in the middle of an edit) formats the same way the second time
	stable("@d{|(())\n}");
	stable("{\n/*\n*/v\no}");
	stable("{\n$if}$endif\nF");
	stable("@e{$if\n;}");
	stable("\t$switch\n\t}\n($endswitch", "c3f_brace_style", "linux");
	stable("1\n\t/*\n*/i/*\nc");
	stable("e\n $foreach\n\t s$endforeach");
	stable("c\n /*\n*/$for\nr$endfor");
	stable("t\n/*\n*/[e\n]", "c3f_continuation", "align");
	stable("struct:h\n{\n}", "c3f_style", "knr");
	stable("$if{\ni}\nr$endif", "c3f_brace_style", "linux");
}

fn void third_review_regressions() @test
{
	// an operator before a prefix operator is spaced on both sides
	check("fn void f()\n{\n\tx=-1;\n\tok=a==-1;\n\tb=!c;\n\tp=*q;\n}\n", "fn void f()\n{\n\tx = -1;\n\tok = a == -1;\n\tb = !c;\n\tp = *q;\n}\n");
	// a blank line after each top-level body, not inside one
	c3f::Config d = c3f::defaults();
	(void)d.set("c3f_decl_spacing", "1");
	check("fn void f()\n{\n\tif (x)\n\t{\n\t}\n\treturn;\n}\nint x;\n", "fn void f()\n{\n\tif (x)\n\t{\n\t}\n\treturn;\n}\n\nint x;\n", &d);
	// values that make no sense are rejected
	c3f::Config c = c3f::defaults();
	assert(@catch(c.set("c3f_wrap_cost_hard", "nan")));
	assert(@catch(c.set("c3f_trailing_comment_spaces", "0")));
}

fn void wrapping_counts_the_indentation_it_writes() @test
{
	// a line broken inside a `{ … }` item is two levels deeper: the layout must see that
	String src = "fn void f()\n{\n\tFoo x = { .alpha = compute_value_one + compute_value_two + compute_three, .beta = other_value_here + more_stuff_more };\n}\n";
	for (int limit = 44; limit <= 47; limit++)
	{
		c3f::Config c = c3f::defaults();
		(void)c.set("max_line_length", string::tformat("%d", limit));
		(void)c.set("c3f_line_breaks", "fit");
		String got = fmt_with(src, &c);
		foreach (line : got.tsplit("\n")) assert(c3f::text_width(line, 0, 4) <= limit, "%d: %s", limit, line);
		assert(fmt_with(got, &c) == got);
	}
}

<* Formatting the result again changes nothing, under these settings. *>
fn void stable_with(String src, String[] settings) @local
{
	c3f::Config cfg = c3f::defaults();
	for (sz i = 0; i + 1 < settings.len; i += 2) (void)cfg.set(settings[i], settings[i + 1]);
	String once = fmt_with(src, &cfg);
	assert(fmt_with(once, &cfg) == once, "not idempotent:\n%s", once);
}

fn void later_wrap_passes_settle() @test
{
	// a pass that wraps nothing may still re-indent what was wrapped (tab and align continuations)
	String call = "fn void f()\n{\n\tx = aaaa(bbbbbbbbbbbbbbbb, cccccccccccccccccccccccccccccccc, dddddddddd(eeeeeeeeeeeeeeee, ffffffffffffffff, gggggggggggggggg, hhhhhhhhhhhhhh));\n}\n";
	stable_with(call, {"max_line_length", "50", "c3f_line_breaks", "long", "c3f_continuation", "tab"});
	stable_with(call, {"max_line_length", "60", "c3f_line_breaks", "long", "c3f_continuation", "align"});
	// an aligned gap before a name does not move the continuation lines that align after its '('
	stable_with("fn int\tget_value(char r,\n\tint b)\n{\n\treturn 1;\n}\n", {"c3f_continuation", "align"});
	// a compile-time header over two lines: the body is judged by the line after its ':'
	check("fn void f()\n{\n\t$if $a &&\n $b:\n\t\tfoo();\n\t$endif\n}\n", "fn void f()\n{\n\t$if $a &&\n\t$b:\n\t\tfoo();\n\t$endif\n}\n");
	stable_with("fn void f()\n{\n\t$if $a &&\n $b:\n\t\tfoo();\n\t$endif\n}\n", {"c3f_continuation", "tab"});
	// several statements on one line are not wrapped (each pass would settle only one more)
	stable_with("const Foo A = { 0x4c5c32ff, 0xbb9d, 0x43b0, x\"b5b42d72e54eaaa4\" };  const Foo B = { 0xb7bede81, 0xdf94, 0x4682, x\"a7d857a52620b86f\" };  const Foo C = { 0xA63293E8, 0x664E, 0x48DB, x\"A079DF759E0509F7\" };\n",
		{"max_line_length", "40", "c3f_line_breaks", "long"});
}
