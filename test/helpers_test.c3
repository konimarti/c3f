module c3f_test;
import c3f, std::io;

<* A configuration with the defaults, then `settings` (key, value, ...) applied in order. *>
fn c3f::Config config_with(String[] settings)
{
	c3f::Config cfg = c3f::defaults();
	for (sz i = 0; i + 1 < settings.len; i += 2) assert(@ok(cfg.set(settings[i], settings[i + 1])));
	return cfg;
}

<* Formats `src` with `cfg`; a second run must change nothing. Returns the first result. *>
fn String settled_cfg(String src, c3f::Config* cfg)
{
	String once = fmt_with(src, cfg);
	String twice = fmt_with(once, cfg);
	if (twice != once) io::eprintfn("--- not idempotent ---\n%s\n--- then ---\n%s\n---", once, twice);
	assert(twice == once);
	return once;
}

<* Formats `src` under the defaults and `settings`; a second run must change nothing. Returns the first result. *>
fn String settled(String src, String[] settings)
{
	c3f::Config cfg = config_with(settings);
	return settled_cfg(src, &cfg);
}

<* Formats `src` under `settings` and checks that a second run changes nothing. *>
fn void stable_with(String src, String[] settings)
{
	(void)settled(src, settings);
}

<* Formats `src` under the defaults, with the option `key` = `value` if key is given. *>
fn void stable(String src, String key = "", String value = "")
{
	(void)settled(src, key.len ? { key, value } : {});
}

<* Formats `src` with `cfg`, checks the result against `want`, and checks that a second run changes nothing. *>
fn void check(String src, String want, c3f::Config* cfg = null)
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
