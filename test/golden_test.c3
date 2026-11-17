module c3f_test;
import c3f, std::collections::list, std::core::mem, std::io, std::io::file, std::io::path, std::sort;

<*
 Golden cases: test/golden/*.golden. A case is three parts, in this order:
   - header: `// c3f_<key>=<value>` lines, applied in order with Config.set;
   - input: the source, up to the line before `// Output` (its final newline is not part of it);
   - `// Output`, then the expected text, byte for byte.
*>
const String GOLDEN_DIR = "test/golden";
const String GOLDEN_EXT = ".golden";
const String SEPARATOR = "// Output";
const String OPTION_PREFIX = "// c3f_";
<* Options without the c3f_ prefix, as in .editorconfig. *>
const String[] PLAIN_OPTIONS = { "indent_style", "indent_size", "tab_width", "end_of_line", "insert_final_newline", "max_line_length" };

fn void golden_cases() @test
{
	PathList? entries = path::ls(tmem, path::tnew(GOLDEN_DIR)!!);
	if (catch entries)
	{
		io::eprintfn("golden: cannot list %s (run the tests from the project root)", GOLDEN_DIR);
		assert(false);
	}
	List{String} names;
	names.tinit();
	foreach (e : entries)
	{
		String n = (String)e;
		if (n.ends_with(GOLDEN_EXT)) names.push(n);
	}
	assert(names.size > 0, "no golden cases in %s", GOLDEN_DIR);
	sort::mergesort(&names, fn int(String a, String b) => a.compare_to(b));

	List{String} failures;
	failures.tinit();
	foreach (name : names) check_golden(string::tformat("%s/%s", GOLDEN_DIR, name), &failures);
	foreach (f : failures) io::eprintfn("%s", f);
	assert(failures.size == 0, "%d of %d golden cases failed", failures.size, names.size);
}

<* Runs one case and appends a report for each failure. *>
fn void check_golden(String file, List{String}* failures) @local
{
	String text = (String)file::load_temp(file)!!;
	c3f::Config cfg = c3f::defaults();

	// header: option lines, up to the first line that is not one
	usz input_start = 0;
	while (input_start < text.len)
	{
		usz end = line_end(text, input_start);
		String line = text[input_start:end - input_start];
		if (!is_option_line(line)) break;
		String body = line[3:line.len - 3];
		usz eq = find_char(body, '=');
		if (eq == body.len)
		{
			failures.push(string::tformat("%s:%d: option line has no '=': %s", file, line_of(text, input_start), line));
			return;
		}
		if (catch cfg.set(body[0:eq], body[eq + 1:body.len - eq - 1], file))
		{
			failures.push(string::tformat("%s:%d: bad option: %s", file, line_of(text, input_start), line));
			return;
		}
		input_start = end + 1;
	}

	// input: up to the separator line
	usz sep_start = input_start;
	while (sep_start < text.len && text[sep_start:line_end(text, sep_start) - sep_start] != SEPARATOR)
	{
		sep_start = line_end(text, sep_start) + 1;
	}
	if (sep_start >= text.len)
	{
		failures.push(string::tformat("%s: no `%s` line", file, SEPARATOR));
		return;
	}
	String input = sep_start > input_start ? text[input_start:sep_start - input_start - 1] : "";

	// expected: everything after the separator line
	usz want_start = line_end(text, sep_start) + 1;
	String want = want_start <= text.len ? text[want_start:text.len - want_start] : "";

	String got = c3f::format(tmem, input, &cfg).text;
	if (got != want)
	{
		failures.push(report(file, text, want_start, want, got, "output differs from the expected text"));
		return;
	}
	String again = c3f::format(tmem, got, &cfg).text;
	if (again != got)
	{
		failures.push(report(file, text, want_start, got, again, "formatting the output again changes it"));
	}
}

<* The index of the newline ending the line at `from`, or text.len. *>
fn usz line_end(String text, usz from) @local
{
	usz i = from;
	while (i < text.len && text[i] != '\n') i++;
	return i;
}

fn usz find_char(String s, char c) @local
{
	usz i = 0;
	while (i < s.len && s[i] != c) i++;
	return i;
}

<* The 1-based line of the byte at `pos`. *>
fn usz line_of(String text, usz pos) @local
{
	usz n = 1;
	for (usz i = 0; i < pos && i < text.len; i++) if (text[i] == '\n') n++;
	return n;
}

<*
 Describes the first byte where `got` differs from `want`: the case file, the line and
 column in the case file (the expected text lives there), both lines, and a caret.
 `want_start` is where the expected text begins in `text`.
*>
fn String report(String file, String text, usz want_start, String want, String got, String what) @local
{
	usz n = want.len < got.len ? want.len : got.len;
	usz j = 0;
	while (j < n && want[j] == got[j]) j++;

	// the line of the first difference, and where it starts
	usz wl = 0;
	usz ws = 0;
	for (usz i = 0; i < j; i++)
	{
		if (want[i] == '\n')
		{
			wl++;
			ws = i + 1;
		}
	}
	String wline = want[ws:line_end(want, ws) - ws];
	String gline = got[ws:line_end(got, ws) - ws];
	usz col = j - ws + 1;

	char[] pad = mem::talloc_array(char, (sz)(col - 1));
	foreach (&c : pad) *c = ' ';
	return string::tformat("%s:%d:%d: %s\n  want: %s\n  got:  %s\n        %s^",
		file, line_of(text, want_start) + wl, col, what, wline, gline, (String)pad);
}

<* Is this a header line: `// c3f_<key>=...`, or `// <key>=...` for a key without the prefix? *>
fn bool is_option_line(String line) @local
{
	if (line.starts_with(OPTION_PREFIX)) return true;
	foreach (k : PLAIN_OPTIONS)
	{
		if (line.starts_with(string::tformat("// %s=", k))) return true;
	}
	return false;
}
