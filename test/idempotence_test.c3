module c3f_test;
import c3f, std::io;

<* Formats under `settings` (key, value, ...); a second run must change nothing. Returns the first result. *>
fn String settle(String src, String[] settings) @local
{
	c3f::Config cfg = c3f::defaults();
	for (sz i = 0; i + 1 < settings.len; i += 2) (void)cfg.set(settings[i], settings[i + 1]);
	String once = fmt_with(src, &cfg);
	String twice = fmt_with(once, &cfg);
	assert(twice == once, "not idempotent:\n%s\n--- then ---\n%s", once, twice);
	return once;
}

fn void sorted_imports_with_no_blank_lines_allowed() @test
{
	String src = "module t;\nimport std::io;\n\nimport abc;\n\nfn void main() {}\n";
	String[] modes = { "lines", "all", "split", "lists" };
	foreach (mode : modes)
	{
		(void)settle(src, { "c3f_sort_imports", mode, "c3f_max_blank_lines", "0" });
		(void)settle(src, { "c3f_sort_imports", mode, "c3f_max_blank_lines", "1" });
	}
	// the runs that blank lines separated are one run once the blank lines are gone
	String got = settle(src, { "c3f_sort_imports", "all", "c3f_max_blank_lines", "0" });
	assert(got == "module t;\nimport abc;\nimport std::io;\nfn void main() {}\n", "got:\n%s", got);
	// with blank lines allowed the runs stay apart
	got = settle(src, { "c3f_sort_imports", "all", "c3f_max_blank_lines", "2" });
	assert(got == src, "got:\n%s", got);
	// a comment that a blank line kept away from its import moves with it once the blank line is gone
	got = settle("module t;\n// c\n\nimport z;\nimport a;\n\n// d\nimport y;\n", { "c3f_style", "strict", "c3f_max_blank_lines", "0" });
	assert(got == "module t;\nimport a;\n// d\nimport y;\n// c\nimport z;\n", "got:\n%s", got);
}
