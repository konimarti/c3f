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
 Format C3 source. The result is checked by lexing it again and comparing it with the input.
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
		r.notes.push({ input[:i].count("\n") + 1, "carriage return without a newline; the file was kept as written".copy(a) });
		r.text = input.copy(a);
		return r;
	}
	Config settled = *cfg;
	settled.finish();
	String text = format_pass(&r, a, input, &settled);
	r.text = text.copy(a);
	r.changed = r.text != input;
	return r;
}

fn String format_pass(FormatResult* r, Allocator a, String input, Config* settled) @local
{
	bool wraps = settled.line_breaks != KEEP && settled.max_line_length != 0;
	WrapMemo memo;
	if (wraps) memo.init();
	defer if (wraps) memo.free();
	String first = format_text(input, settled, r, a, wraps ? &memo : null);
	String text = first;
	// `wrap_rewrite`: a body that cannot move to the next line without braces gets them (and the statement is
	// joined again); the next pass lays it out
	if (settled.line_breaks == WRAP_REWRITE && !r.fallback) text = brace_long_bodies(first, settled);
	// wrapping can turn one statement into several (a '{' that now ends a line opens a block),
	// which the next run may wrap again: repeat until nothing changes, so a second run never does
	// (if the first pass wrapped nothing, the text is formatted as without wrapping: one run is enough)
	if (wraps && (memo.wrapped || text != first))
	{
		// the notes are about the input; a later pass that cannot be verified is not used
		FormatResult later;
		later.notes.tinit();
		// (the lines a split string adds can move what was wrapped before: one more pass)
		int passes = settled.line_breaks == WRAP_REWRITE ? WRAP_PASSES + 1 : WRAP_PASSES;
		bool unlaid = text != first;
		for (int pass = 1; pass < passes; pass++)
		{
			memo.wrapped = 0;
			String again = format_text(text, settled, &later, tmem, &memo, attempts: 1, sort: false);   // (sorted by the first pass)
			if (again == text)
			{
				// (braces that were not laid out: the pass failed)
				if (unlaid) text = first;
				break;
			}
			text = again;
			unlaid = false;
			if (!memo.wrapped) break;   // (it may still have re-indented what was wrapped before)
		}
	}
	return text;
}

<* Format once; a place whose result cannot be verified is kept as written and the rest is tried again. *>
fn String format_text(String original, Config* cfg, FormatResult* r, Allocator a, WrapMemo* memo, int attempts = MAX_ATTEMPTS, bool sort = true) @local
{
	String input = original;
	if (sort && cfg.sort_imports != OFF)
	{
		String sorted = sort_imports(original, cfg.sort_imports);
		if (sorted != original && same_tokens(original, sorted, cfg.sort_imports == SPLIT)) input = sorted;
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
		r.notes.push({ t.line, string::format(a, "%s '%s'; kept as written %s", what, t.text, upto) });
	}
	Fmt f;
	f.init(&s, cfg);
	f.memo = memo;
	List{String} texts;
	texts.tinit();
	sz noted = r.notes.len();
	for (int attempt = 1; ; attempt++)
	{
		f.breaks();
		f.layout();
		f.wrap();
		f.align();
		f.split_strings();
		String output = f.emit(&texts);
		sz bad = f.verify(output, &texts);
		if (bad == NO) return output;
		if (attempt == attempts)
		{
			if (attempts == 1) return original;   // a later pass: the input is a verified result already
			// the places noted so far are part of the file, which is kept as a whole
			while (r.notes.len() > noted) free_note(r.notes.pop()!!, a);
			r.fallback = true;
			r.notes.push({ s.toks[bad].line, "could not be formatted safely; the file was kept as written".copy(a) });
			return original;
		}
		r.fallback = true;
		r.notes.push({ s.toks[bad].line, "could not be formatted safely; kept as written".copy(a) });
		s.keep_range(bad > 0 ? bad - 1 : 0, bad + 1);
	}
}

<*
 Do a and b hold the same tokens, in any order? (A reordering must not lose or add any.)
 Splitting import lists changes the number of `import`, `,` and `;`, so those are left out then.
*>
fn bool same_tokens(String a, String b, bool split) @local
{
	List{String} ta = token_texts(a, split);
	List{String} tb = token_texts(b, split);
	if (ta.len() != tb.len()) return false;
	sort::mergesort(&ta, fn int(String x, String y) => x.compare_to(y));
	sort::mergesort(&tb, fn int(String x, String y) => x.compare_to(y));
	foreach (i, t : ta) if (t != tb[i]) return false;
	return true;
}

fn List{String} token_texts(String text, bool split) @local
{
	List{String} l;
	l.tinit();
	Lexer lx;
	lx.init(text);
	while (try t = lx.next())
	{
		if (t.type == EOF) break;
		if (split && (t.type == IMPORT || t.type == COMMA || t.type == EOS)) continue;
		l.push(t.text);
	}
	return l;
}
