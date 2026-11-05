module c3f;
import c3::lexer, std::collections::list, std::sort;

struct Note
{
	sz     line;
	String text;
}

<* Replace input bytes [start, end) with `text`. *>
struct TextEdit
{
	sz     start, end;
	String text;
}

struct FormatResult
{
	String         text;
	bool           changed;
	bool           fallback;   // a place could not be formatted safely and was kept as written
	List{Note}     notes;
}

fn void FormatResult.free(&self)
{
	alloc::free(self.notes.allocator, self.text.ptr);
	foreach (n : self.notes) alloc::free(self.notes.allocator, n.text.ptr);
	self.notes.free();
}

const int MAX_ATTEMPTS = 8;
const int WRAP_PASSES = 3;

<*
 Format C3 source. Only whitespace changes; the result is checked by lexing it again.
 @param a : "allocator for the result"
*>
fn FormatResult format(Allocator a, String input, Config* cfg) => @pool()
{
	FormatResult r;
	r.notes.init(a);
	Config settled = *cfg;
	settled.finish();
	String text = format_text(input, &settled, &r, a);
	// wrapping can turn one statement into several (a '{' that now ends a line opens a block),
	// which the next run may wrap again: repeat until nothing changes, so a second run never does
	if (settled.line_breaks != PRESERVE)
	{
		for (int pass = 1; pass < WRAP_PASSES; pass++)
		{
			String again = format_text(text, &settled, &r, a);
			if (again == text) break;
			text = again;
		}
	}
	r.text = text.copy(a);
	r.changed = r.text != input;
	return r;
}

<*
 The edits that turn `old` into `new` (e.g. an input and its formatted text): one per changed
 gap or token. If the two do not hold the same tokens in the same order (sorted imports), one
 edit replaces everything. The edit texts are slices of `new`.
*>
fn TextEdit[] edits(Allocator a, String old, String new) => @pool()
{
	List{TextEdit} l;
	l.tinit();
	diff_tokens(old, new, &l);
	return l.to_array(a);
}

fn void diff_tokens(String old, String new, List{TextEdit}* edits) @local
{
	List{Token} a = all_tokens(old);
	List{Token} b = all_tokens(new);
	bool same = a.len() == b.len();
	// the same tokens in the same order; only gaps (and re-indented comment lines) differ
	for (sz i = 0; same && i < a.len(); i++) same = a[i].type == b[i].type && (a[i].text == b[i].text || is_comment_type(a[i].type));
	if (!same)
	{
		edits.push({0, old.len, new});
		return;
	}
	sz pa = 0;
	sz pb = 0;
	for (sz i = 0; i <= a.len(); i++)
	{
		sz sa = i < a.len() ? a[i].offset : old.len;
		sz sb = i < b.len() ? b[i].offset : new.len;
		if (old[pa:sa - pa] != new[pb:sb - pb]) edits.push({pa, sa, new[pb:sb - pb]});
		if (i == a.len()) break;
		if (a[i].text != b[i].text) edits.push({sa, sa + a[i].len, b[i].text});
		pa = sa + a[i].len;
		pb = sb + b[i].len;
	}
}

fn List{Token} all_tokens(String text) @local
{
	List{Token} l;
	l.tinit();
	Lexer lx;
	lx.init(text);
	while (try t = lx.next())
	{
		if (t.type == EOF) break;
		l.push(t);
	}
	return l;
}

<*
 Format only the part of `input` between byte offsets start and end (for editors): the
 edits that overlap [start, end) are applied, everything else stays as it is.
*>
fn String format_range(Allocator a, String input, sz start, sz end, Config* cfg) => @pool()
{
	Config local = *cfg;
	local.sort_imports = OFF;   // reordering is never part of formatting a range
	FormatResult r = format(tmem, input, &local);
	DString d;
	d.tinit();
	sz at = 0;
	foreach (e : edits(tmem, input, r.text))
	{
		bool overlaps = e.start == e.end ? e.start >= start && e.start <= end : e.start < end && e.end > start;
		if (!overlaps) continue;
		d.append(input[at:e.start - at]);
		d.append(e.text);
		at = e.end;
	}
	d.append(input[at..]);
	return d.copy_str(a);
}

fn String format_text(String original, Config* cfg, FormatResult* r, Allocator a) @local
{
	String input = original;
	if (cfg.sort_imports != OFF)
	{
		String sorted = sort_imports(original, cfg.sort_imports);
		if (same_tokens(original, sorted)) input = sorted;
	}
	Src s;
	s.init(input);
	if (s.len() == 0) return input.trim().len == 0 ? "" : input;
	sort::quicksort(&s.unbalanced);
	foreach (b : s.unbalanced)
	{
		r.fallback = true;
		String what = is_opener(s.toks[b].type) ? "unclosed" : "unopened";
		r.notes.push({s.toks[b].line, string::format(a, "%s '%s'; the code it encloses was kept as written", what, s.toks[b].text)});
	}
	Fmt f;
	f.init(&s, cfg);
	List{String} texts;
	texts.tinit();
	for (int attempt = 0; ; attempt++)
	{
		f.breaks();
		f.layout();
		f.wrap();
		f.align();
		String output = f.emit(&texts);
		sz bad = f.verify(output, &texts);
		if (bad == NO) return output;
		r.fallback = true;
		r.notes.push({s.toks[bad].line, "could not be formatted safely; kept as written".copy(a)});
		if (attempt + 1 == MAX_ATTEMPTS) return original;
		s.keep_range(bad > 0 ? bad - 1 : 0, bad + 1);
	}
}

<* Do a and b hold the same tokens, in any order? (A reordering must not lose or add any.) *>
fn bool same_tokens(String a, String b) @local
{
	List{String} ta = token_texts(a);
	List{String} tb = token_texts(b);
	if (ta.len() != tb.len()) return false;
	sort::quicksort(&ta, fn int(String x, String y) => x.compare_to(y));
	sort::quicksort(&tb, fn int(String x, String y) => x.compare_to(y));
	foreach (i, t : ta) if (t != tb[i]) return false;
	return true;
}

fn List{String} token_texts(String text) @local
{
	List{String} l;
	l.tinit();
	Lexer lx;
	lx.init(text);
	while (try t = lx.next())
	{
		if (t.type == EOF) break;
		l.push(t.text);
	}
	return l;
}
