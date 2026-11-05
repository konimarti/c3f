module c3f;
import c3::lexer, std::collections::list, std::sort;

<* A piece of source that moves as a whole: an import statement (with its comments) or one module of it. *>
struct Unit @local
{
	sz     first, last;    // token range
	String key;            // module path, e.g. "std::io::file"
}

<* Compare module paths segment by segment ("std::io" < "std::io::file" < "std::math"). *>
fn int compare_paths(String a, String b)
{
	while (true)
	{
		sz ia = @ok(a.index_of("::")) ? a.index_of("::")!! : a.len;
		sz ib = @ok(b.index_of("::")) ? b.index_of("::")!! : b.len;
		int c = a[:ia].compare_to(b[:ib]);
		if (c != 0) return c;
		bool ea = ia == a.len;
		bool eb = ib == b.len;
		if (ea || eb) return ea == eb ? 0 : ea ? -1 : 1;
		a = a[ia + 2..];
		b = b[ib + 2..];
	}
}

// (the sorts are merge sorts: stable, so equal paths keep their order)
fn int compare_units(Unit a, Unit b) @local => compare_paths(a.key, b.key);

<* The module path starting at token k. *>
fn String Src.path_at(&self, sz k)
{
	DString d;
	d.tinit();
	for (; k < self.len(); k++)
	{
		Tok* t = &self.toks[k];
		if (t.type != IDENT && t.type != SCOPE && t.type != TYPE_IDENT && t.type != CONST_IDENT) break;
		d.append(t.text);
	}
	return d.str_view();
}

<* Source text of tokens a..b, inside whitespace included. *>
fn String Src.span_text(&self, sz a, sz b) => self.text[self.toks[a].start:self.end(b) - self.toks[a].start];

fn bool Src.has_keep(&self, sz a, sz b)
{
	for (sz k = a; k <= b; k++) if (self.toks[k].keep) return true;
	return false;
}

<*
 Sort imports: `lines` reorders the import statements of a run (no blank
 line between them), `lists` sorts the modules inside one statement. Comments directly
 above a statement and after it on the same line move with it. Returns the new text.
*>
fn String sort_imports(String text, SortImports mode)
{
	if (mode == OFF) return text;
	if (text.starts_with("\xEF\xBB\xBF")) return "\xEF\xBB\xBF".tconcat(sort_imports(text[3..], mode));
	Src s;
	s.init(text);
	List{Unit} stmts;
	stmts.tinit();
	for (sz i = 0; i < s.len(); i++)
	{
		Tok* t = &s.toks[i];
		if (t.type != IMPORT || t.encl != NO) continue;
		sz end = i;
		while (end < s.len() && s.toks[end].type != EOS) end++;
		if (end >= s.len()) break;
		Unit u = {.first = i, .last = end, .key = s.path_at(i + 1)};
		// comments in front of it (on its line, or on their own lines right above) move with it
		while (u.first > 0 && !s.toks[u.first - 1].code)
		{
			bool same_line = s.toks[u.first].nl == 0;
			bool own_line_above = s.toks[u.first].nl == 1 && (u.first - 1 == 0 || s.toks[u.first - 1].nl > 0);
			if (!same_line && !own_line_above) break;
			u.first--;
		}
		// and a comment after it, if that comment ends the line
		bool ends_line = end + 2 >= s.len() || s.toks[end + 2].nl > 0;
		if (end + 1 < s.len() && !s.toks[end + 1].code && s.toks[end + 1].nl == 0 && ends_line) u.last = end + 1;
		// only statements on lines of their own move: the gaps between them must all be line breaks
		bool own_line = (u.first == 0 || s.toks[u.first].nl > 0) && (u.last + 1 >= s.len() || s.toks[u.last + 1].nl > 0);
		if (!s.has_keep(u.first, u.last) && own_line) stmts.push(u);
		i = end;
	}
	if (!stmts.len()) return text;
	DString out;
	out.tinit();
	sz copied = 0;   // byte offset copied so far
	sz r = 0;
	while (r < stmts.len())
	{
		// a run: statements separated by exactly one line break
		sz r2 = r;
		while (r2 + 1 < stmts.len() && stmts[r2 + 1].first == stmts[r2].last + 1 && s.toks[stmts[r2 + 1].first].nl == 1) r2++;
		List{Unit} run;
		run.tinit();
		for (sz k = r; k <= r2; k++) run.push(stmts[k]);
		List{String} texts;
		texts.tinit();
		foreach (k, u : run)
		{
			String body = s.span_text(u.first, u.last);
			if (mode == LISTS || mode == ALL) body = sort_list(&s, &run[k], body);
			texts.push(body);
		}
		List{sz} order;
		order.tinit();
		for (sz k = 0; k < run.len(); k++) order.push(k);
		if ((mode == LINES || mode == ALL) && run.len() > 1)
		{
			sort::mergesort(&order, fn int(sz a, sz b, List{Unit}* run) => compare_units((*run)[a], (*run)[b]), &run);
		}
		// write: everything before the run, then the units in their new order with the old gaps
		out.append(text[copied:s.toks[run[0].first].start - copied]);
		foreach (k, o : order)
		{
			if (k > 0) out.append(s.gap(run[k].first));
			out.append(texts[o]);
		}
		copied = s.end(run[^1].last);
		r = r2 + 1;
	}
	out.append(text[copied..]);
	return out.str_view();
}

<* `import b, a @attr;` → `import a, b @attr;`; each module moves with its own attributes. *>
fn String sort_list(Src* s, Unit* u, String body) @local
{
	List{Unit} items;
	items.tinit();
	// the unit may start with the comment above the statement
	sz imp = u.first;
	while (s.toks[imp].type != IMPORT) imp++;
	sz from = imp + 1;
	sz stmt_end = imp;
	while (s.toks[stmt_end].type != EOS) stmt_end++;
	for (sz k = from; k <= stmt_end; k++)
	{
		Tok* t = &s.toks[k];
		if (!t.code) return body;   // a comment inside: leave the list alone
		if (t.type != COMMA && t.type != EOS) continue;
		if (k == from) return body;
		items.push({.first = from, .last = k - 1, .key = s.path_at(from)});
		from = k + 1;
	}
	if (items.len() < 2) return body;
	List{Unit} sorted;
	sorted.tinit();
	foreach (it : items) sorted.push(it);
	sort::mergesort(&sorted, &compare_units);
	u.key = sorted[0].key;   // the statement now sorts by its first module
	DString d;
	d.tinit();
	d.append(s.text[s.toks[u.first].start:s.toks[imp].start - s.toks[u.first].start]);   // a comment above
	d.append(s.span_text(imp, imp));                     // "import"
	foreach (k, it : sorted)
	{
		// the separators stay where they were: "import" + gap, then ", " (or whatever was written)
		if (k == 0)
		{
			d.append(s.gap(items[0].first));
		}
		else
		{
			sz sep = s.end(items[k - 1].last);
			d.append(s.text[sep:s.toks[items[k].first].start - sep]);
		}
		d.append(s.span_text(it.first, it.last));
	}
	// from the end of the last item to the end of the unit (';' and a trailing comment)
	sz tail_from = s.end(items[^1].last);
	d.append(s.text[tail_from:s.end(u.last) - tail_from]);
	return d.str_view();
}
