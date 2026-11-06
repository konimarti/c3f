module c3f;
import std::io, std::collections::list;

enum Edit : char @local { SAME, DEL, ADD }

struct Op @local
{
	Edit kind;
	sz   a, b;    // line index in old / new
}

<* Lines without their '\n'; a last line without one is marked so it differs from the same text with one. *>
struct Lines @local
{
	List{String} text;
	bool         open_end;   // the last line has no '\n'
}

fn Lines split_lines(String s) @local
{
	Lines l;
	l.text.tinit();
	sz from = 0;
	foreach (i, c : s)
	{
		if (c != '\n') continue;
		l.text.push(s[from:i - from]);
		from = i + 1;
	}
	if (from < s.len)
	{
		l.text.push(s[from..]);
		l.open_end = true;
	}
	return l;
}

fn bool same_line(Lines* x, sz i, Lines* y, sz j) @local
{
	if (x.text[i] != y.text[j]) return false;
	bool xe = x.open_end && i == x.text.len() - 1;
	bool ye = y.open_end && j == y.text.len() - 1;
	return xe == ye;
}

const sz MAX_EDITS = 2000;

<*
 Shortest edit script (Myers). Each step keeps only the diagonals it reached, so memory grows
 with the square of the number of edits, not with the file. Past MAX_EDITS: replace everything.
*>
fn List{Op} edit_script(Lines* x, Lines* y) @local
{
	sz n = x.text.len();
	sz m = y.text.len();
	sz max = n + m;
	List{Op} ops;
	ops.tinit();
	List{sz[]} trace;   // trace[d][k + d]: furthest x on diagonal k before step d
	trace.tinit();
	sz[] v = mem::talloc_array(sz, 2 * max + 3);
	v[..] = 0;
	sz off = max + 1;
	sz found = -1;
	for (sz d = 0; d <= max && d <= MAX_EDITS; d++)
	{
		sz[] snapshot = mem::talloc_array(sz, 2 * d + 1);
		for (sz k = -d; k <= d; k++) snapshot[k + d] = v[off + k];
		trace.push(snapshot);
		for (sz k = -d; k <= d; k += 2)
		{
			sz xi = k == -d || (k != d && v[off + k - 1] < v[off + k + 1]) ? v[off + k + 1] : v[off + k - 1] + 1;
			sz yi = xi - k;
			while (xi < n && yi < m && same_line(x, xi, y, yi))
			{
				xi++;
				yi++;
			}
			v[off + k] = xi;
			if (xi >= n && yi >= m)
			{
				found = d;
				break;
			}
		}
		if (found >= 0) break;
	}
	if (found < 0)
	{
		for (sz i = 0; i < n; i++) ops.push({DEL, i, 0});
		for (sz j = 0; j < m; j++) ops.push({ADD, n, j});
		return ops;
	}
	List{Op} rev;
	rev.tinit();
	sz xi = n;
	sz yi = m;
	for (sz d = found; d > 0; d--)
	{
		sz[] pv = trace[d];
		sz k = xi - yi;
		bool down = k == -d || (k != d && pv[k - 1 + d] < pv[k + 1 + d]);
		sz pk = down ? k + 1 : k - 1;
		sz px = pv[pk + d];
		sz py = px - pk;
		// the snake after the edit
		while (xi > px && yi > py && (down ? yi > py + 1 : xi > px + 1))
		{
			xi--;
			yi--;
			rev.push({SAME, xi, yi});
		}
		rev.push(down ? (Op){ADD, px, py} : (Op){DEL, px, py});
		xi = px;
		yi = py;
	}
	while (xi > 0 && yi > 0)
	{
		xi--;
		yi--;
		rev.push({SAME, xi, yi});
	}
	for (sz i = rev.len(); i > 0; i--) ops.push(rev[i - 1]);
	return ops;
}

const sz CONTEXT = 3;

<* A unified diff (3 lines of context) from `old` to `new`, or "" if they are equal. *>
fn String unified_diff(Allocator a, String name, String old, String new) => @pool()
{
	if (old == new) return "";
	DString d;
	d.tinit();
	write_diff(&d, name, old, new);
	return d.copy_str(a);
}

<* "a/src/x.c3" for a relative name; an absolute name keeps its single leading '/'. *>
fn String diff_path(String side, String name) @local
{
	while (name.starts_with("./")) name = name[2..];
	return name.starts_with("/") ? side.tconcat(name) : string::tformat("%s/%s", side, name);
}

fn void write_line(DString* out, char mark, Lines* l, sz i) @local
{
	out.appendf("%c%s\n", mark, l.text[i]);
	if (l.open_end && i == l.text.len() - 1) out.append("\\ No newline at end of file\n");
}

fn void write_diff(DString* out, String name, String old, String new) @local
{
	Lines x = split_lines(old);
	Lines y = split_lines(new);
	List{Op} ops = edit_script(&x, &y);
	out.appendf("--- %s\n", diff_path("a", name));
	out.appendf("+++ %s\n", diff_path("b", name));
	sz i = 0;
	while (i < ops.len())
	{
		if (ops[i].kind == SAME)
		{
			i++;
			continue;
		}
		// a hunk: CONTEXT lines around a run of changes closer than 2 * CONTEXT to each other
		sz start = i >= CONTEXT ? i - CONTEXT : 0;
		sz end = i;
		sz same_run = 0;
		for (sz k = i; k < ops.len(); k++)
		{
			if (ops[k].kind != SAME)
			{
				same_run = 0;
				end = k;
			}
			else if (++same_run > 2 * CONTEXT)
			{
				break;
			}
		}
		sz stop = min(end + CONTEXT + 1, ops.len());
		sz a_len, b_len;
		for (sz k = start; k < stop; k++)
		{
			if (ops[k].kind != ADD) a_len++;
			if (ops[k].kind != DEL) b_len++;
		}
		sz a_from = ops[start].a;
		sz b_from = ops[start].b;
		out.appendf("@@ -%d,%d +%d,%d @@\n", a_len ? a_from + 1 : a_from, a_len, b_len ? b_from + 1 : b_from, b_len);
		for (sz k = start; k < stop; k++)
		{
			switch (ops[k].kind)
			{
				case SAME: write_line(out, ' ', &x, ops[k].a);
				case DEL: write_line(out, '-', &x, ops[k].a);
				case ADD: write_line(out, '+', &y, ops[k].b);
			}
		}
		i = stop;
	}
}
