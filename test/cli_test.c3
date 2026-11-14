module c3f_test;
import c3f, c3f::cli, std::io;

const String BROKEN = "fn void g(){int a=1;}\nfn void f()\n{\n\tif (x>0 {\n\t\tfoo( a );\n\t}\n}\n";

<* Writes `text` to a new file in the temp directory and returns its path. *>
fn String temp_file(String name, String text) @local
{
	String path = (String)path::temp_directory(tmem)!!.tappend(string::tformat("c3f_cli_%s", name))!!;
	assert(@ok(file::save(path, text)));
	return path;
}

fn void write_keeps_place_and_exits_ok() @test
{
	String path = temp_file("write_kept.c3", BROKEN);
	defer (void)file::delete(path);
	c3f::Config cfg = c3f::defaults();
	cli::Options opt;
	opt.mode = WRITE;
	assert(cli::run(&opt, path, BROKEN, &cfg) == cli::Status.OK);
	String got = (String)file::load_temp(path)!!;
	// the formatted part and the rest kept as written
	assert(got.starts_with("fn void g() {int a = 1;}\n"));
	assert(got.contains("\tif (x>0 {\n\t\tfoo( a );"));
}

fn void check_keeps_exit_3() @test
{
	c3f::Config cfg = c3f::defaults();
	cli::Options opt;
	opt.mode = CHECK;
	assert(cli::run(&opt, "kept.c3", BROKEN, &cfg) == cli::Status.KEPT);
	assert(cli::Status.KEPT.ordinal == 3);
	assert(cli::run(&opt, "changed.c3", "fn void f(){int a=1;}\n", &cfg) == cli::Status.CHANGED);
}

fn bool same_options(cli::Options* a, cli::Options* b) @local
{
	return a.mode == b.mode && a.stdin == b.stdin && a.help == b.help && a.version == b.version
		&& a.git_hook == b.git_hook && a.config == b.config && a.stdin_filename == b.stdin_filename
		&& a.sets.len() == b.sets.len() && a.excludes.len() == b.excludes.len() && a.paths.len() == b.paths.len();
}

fn void vscode_flags_are_the_stdin_flags() @test
{
	cli::Options want;
	assert(@ok(want.parse({ "c3f", "-", "--stdin-filename", "/x/a.c3" })));
	assert(want.stdin && want.stdin_filename == "/x/a.c3");
	cli::Options got;
	assert(@ok(got.parse({ "c3f", "--stdin", "--stdout", "--stdin-filepath=/x/a.c3" })));
	assert(same_options(&want, &got));
	cli::Options spaced;
	assert(@ok(spaced.parse({ "c3f", "--stdin", "--stdout", "--stdin-filepath", "/x/a.c3" })));
	assert(same_options(&want, &spaced));
}

fn void stdout_does_not_combine_with_other_modes() @test
{
	String[4] modes = { "-w", "--check", "--diff", "--print-config" };
	foreach (mode : modes)
	{
		cli::Options a;
		assert(!@ok(a.parse({ "c3f", "--stdout", mode, "x.c3" })));
		cli::Options b;
		assert(!@ok(b.parse({ "c3f", mode, "--stdout", "x.c3" })));
	}
	cli::Options ok;
	assert(@ok(ok.parse({ "c3f", "--stdout", "x.c3" })));
}

fn void help_lists_the_vscode_flags() @test
{
	assert(cli::HELP.contains("--stdin-filepath"));
}

extern fn CInt hard_link(ZString existing, ZString created) @cname("link") @feat(POSIX);

<* A file with another hard link is rewritten in place, so both names see the new text. *>
fn void write_keeps_hard_links() @test
{
	$if env::POSIX:
		String src = "fn void f(){int a=1;}\n";
		String path = temp_file("write_link_a.c3", src);
		String other = string::tformat("%s.link", path);
		defer (void)file::delete(path);
		defer (void)file::delete(other);
		(void)file::delete(other);
		assert(hard_link(path.zstr_tcopy(), other.zstr_tcopy()) == 0);
		c3f::Config cfg = c3f::defaults();
		cli::Options opt;
		opt.mode = WRITE;
		assert(cli::run(&opt, path, src, &cfg) == cli::Status.OK);
		String a = (String)file::load_temp(path)!!;
		String b = (String)file::load_temp(other)!!;
		assert(a.contains("int a = 1;"), "got: %s", a);
		assert(b == a, "the other link was left with: %s", b);
		// no temporary file is left next to it
		assert(!@ok(file::load_temp(string::tformat("%s.c3f~", path))));
	$endif
}

<* The temporary file has a name of its own: a file that happens to have the old fixed name is not touched. *>
fn void write_leaves_a_file_with_the_old_temporary_name_alone() @test
{
	String src = "fn void f(){int a=1;}\n";
	String path = temp_file("write_tmpname.c3", src);
	String old = string::tformat("%s.c3f~", path);
	defer (void)file::delete(path);
	defer (void)file::delete(old);
	assert(@ok(file::save(old, "somebody else's file")));
	c3f::Config cfg = c3f::defaults();
	cli::Options opt;
	opt.mode = WRITE;
	assert(cli::run(&opt, path, src, &cfg) == cli::Status.OK);
	assert((String)file::load_temp(old)!! == "somebody else's file");
	assert(((String)file::load_temp(path)!!).contains("int a = 1;"));
}

<* A name of 240 bytes (the limit is 255) leaves no room for a long suffix: the temporary file has a short name of its own. *>
fn void write_a_file_with_a_long_name() @test
{
	$if env::POSIX:
		String src = "fn void f(){int a=1;}\n";
		DString name;
		name.tinit();
		for (int i = 0; i < 229; i++) name.append_char('x');
		name.append(".c3");
		String path = temp_file(name.str_view(), src);
		defer (void)file::delete(path);
		c3f::Config cfg = c3f::defaults();
		cli::Options opt;
		opt.mode = WRITE;
		assert(cli::run(&opt, path, src, &cfg) == cli::Status.OK);
		assert(((String)file::load_temp(path)!!).contains("int a = 1;"));
	$endif
}

<* On POSIX a backslash is part of a name, not a separator: a long name with one still gets a short temporary name. *>
fn void write_a_long_name_with_a_backslash() @test
{
	$if env::POSIX:
		String src = "fn void f(){int a=1;}\n";
		DString name;
		name.tinit();
		for (int i = 0; i < 227; i++) name.append_char('x');
		name.append("\\.c3");
		String path = temp_file(name.str_view(), src);
		defer (void)file::delete(path);
		c3f::Config cfg = c3f::defaults();
		cli::Options opt;
		opt.mode = WRITE;
		assert(cli::run(&opt, path, src, &cfg) == cli::Status.OK);
		assert(((String)file::load_temp(path)!!).contains("int a = 1;"));
	$endif
}
