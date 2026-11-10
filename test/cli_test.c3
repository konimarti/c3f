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
