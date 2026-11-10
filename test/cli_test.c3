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
