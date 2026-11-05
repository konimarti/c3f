module c3f;
import c3::lexer, std::collections::list, std::sort;

struct Note
{
	sz     line;
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
	foreach (n : self.notes) free_note(n, self.notes.allocator);
	self.notes.free();
}

fn void free_note(Note n, Allocator a) @local => alloc::free(a, n.text.ptr);

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
	// c3c drops a '\r' that is not part of "\r\n" before it reads the file, so a comment goes on
	// past it; formatting would have to agree on where that comment ends: keep the file
	foreach (i, c : input)
	{
		if (c != '\r' || (i + 1 < input.len && input[i + 1] == '\n')) continue;
		r.fallback = true;
		r.notes.push({input[:i].count("\n") + 1, "carriage return without a newline; the file was kept as written".copy(a)});
		r.text = input.copy(a);
		return r;
	}
	Config settled = *cfg;
	settled.finish();
	String text = format_text(input, &settled, &r, a);
	// wrapping can turn one statement into several (a '{' that now ends a line opens a block),
	// which the next run may wrap again: repeat until nothing changes, so a second run never does
	if (settled.line_breaks != PRESERVE)
	{
		// the notes are about the input; a later pass that cannot be verified is not used
		FormatResult later;
		later.notes.tinit();
		for (int pass = 1; pass < WRAP_PASSES; pass++)
		{
			String again = format_text(text, &settled, &later, tmem, attempts: 1);
			if (again == text) break;
			text = again;
		}
	}
	r.text = text.copy(a);
	r.changed = r.text != input;
	return r;
}

<* Format once; a place whose result cannot be verified is kept as written and the rest is tried again. *>
fn String format_text(String original, Config* cfg, FormatResult* r, Allocator a, int attempts = MAX_ATTEMPTS) @local
{
	String input = original;
	if (cfg.sort_imports != OFF)
	{
		String sorted = sort_imports(original, cfg.sort_imports);
		if (sorted != original && same_tokens(original, sorted)) input = sorted;
	}
	Src s;
	s.init(input);
	if (s.len() == 0) return input.trim().len == 0 ? "" : input;
	sort::mergesort(&s.unbalanced, fn int(Damage x, Damage y) => x.tok < y.tok ? -1 : x.tok > y.tok ? 1 : 0);
	foreach (d : s.unbalanced)
	{
		r.fallback = true;
		Tok* t = &s.toks[d.tok];
		String what = is_opener(t.type) ? "unclosed" : "unopened";
		String upto = d.last == s.len() - 1 ? "to the end of the file" : string::tformat("up to line %d", s.toks[d.last].line);
		r.notes.push({t.line, string::format(a, "%s '%s'; kept as written %s", what, t.text, upto)});
	}
	Fmt f;
	f.init(&s, cfg);
	List{String} texts;
	texts.tinit();
	sz noted = r.notes.len();
	for (int attempt = 1; ; attempt++)
	{
		f.breaks();
		f.layout();
		f.wrap();
		f.align();
		String output = f.emit(&texts);
		sz bad = f.verify(output, &texts);
		if (bad == NO) return output;
		if (attempt == attempts)
		{
			if (attempts == 1) return original;   // a later pass: the input is a verified result already
			// the places noted so far are part of the file, which is kept as a whole
			while (r.notes.len() > noted) free_note(r.notes.pop()!!, a);
			r.fallback = true;
			r.notes.push({s.toks[bad].line, "could not be formatted safely; the file was kept as written".copy(a)});
			return original;
		}
		r.fallback = true;
		r.notes.push({s.toks[bad].line, "could not be formatted safely; kept as written".copy(a)});
		s.keep_range(bad > 0 ? bad - 1 : 0, bad + 1);
	}
}

<* Do a and b hold the same tokens, in any order? (A reordering must not lose or add any.) *>
fn bool same_tokens(String a, String b) @local
{
	List{String} ta = token_texts(a);
	List{String} tb = token_texts(b);
	if (ta.len() != tb.len()) return false;
	sort::mergesort(&ta, fn int(String x, String y) => x.compare_to(y));
	sort::mergesort(&tb, fn int(String x, String y) => x.compare_to(y));
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
