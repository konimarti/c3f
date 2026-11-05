module c3f;
import std::collections::list;

<*
 Glob matching as in .editorconfig: `*` (not across '/'), `**`, `?`, `[abc]`, `[!abc]`,
 `{a,b,c}`. The `{}` alternatives are expanded first, then each is matched with a memo of
 (pattern position, text position), so `*a*a*a*b` cannot take exponential time.
*>
fn bool glob_match(String pattern, String text) => @pool()
{
	List{String} alts;
	alts.tinit();
	expand_braces(pattern, &alts);
	foreach (alt : alts)
	{
		@pool()
		{
			// one memo at a time: up to MAX_ALTERNATIVES of them would not all fit
			char[] memo = mem::talloc_array(char, (alt.len + 1) * (text.len + 1));
			memo[..] = 0;
			Glob g = {alt, text, memo};
			if (g.at(0, 0)) return true;
		};
	}
	return false;
}

// expansions of `{…}` past this are not made (the pattern then just does not match them)
const sz MAX_ALTERNATIVES = 1024;

<* `a{b,c}d` → `abd`, `acd`; the first `}` after a `{` closes it. *>
fn void expand_braces(String pattern, List{String}* out) @local
{
	if (out.len() >= MAX_ALTERNATIVES) return;
	for (sz i = 0; i < pattern.len; i++)
	{
		if (pattern[i] == '\\')
		{
			i++;
			continue;
		}
		if (pattern[i] != '{') continue;
		String after = pattern[i + 1..];
		sz? close = after.index_of_char('}');
		if (catch close) break;
		String head = pattern[:i];
		String rest = after[close + 1..];
		String alts = after[:close];
		sz from = 0;
		for (sz k = 0; k <= alts.len; k++)
		{
			if (k < alts.len && alts[k] != ',') continue;
			expand_braces(head.tconcat(alts[from:k - from]).tconcat(rest), out);
			from = k + 1;
		}
		return;
	}
	out.push(pattern);
}

struct Glob @local
{
	String pattern;
	String text;
	char[] memo;   // per (pattern index, text index): 0 unknown, 1 no, 2 yes
}

fn bool Glob.at(&self, sz p, sz t)
{
	char* m = &self.memo[p * (self.text.len + 1) + t];
	if (*m) return *m == 2;
	bool r = self.step(p, t);
	*m = r ? 2 : 1;
	return r;
}

fn bool Glob.step(&self, sz p, sz t)
{
	String pat = self.pattern;
	String text = self.text;
	if (p == pat.len) return t == text.len;
	char c = pat[p];
	switch (c)
	{
		case '*':
			bool deep = p + 1 < pat.len && pat[p + 1] == '*';
			sz rest = p + (deep ? 2 : 1);
			for (sz k = t; k <= text.len; k++)
			{
				if (self.at(rest, k)) return true;
				if (k < text.len && text[k] == '/' && !deep) return false;
			}
			return false;
		case '?':
			return t < text.len && text[t] != '/' && self.at(p + 1, t + 1);
		case '[':
			if (try close = pat[p..].index_of_char(']'))
			{
				if (close > 1 && t < text.len)
				{
					String set = pat[p + 1:close - 1];
					bool negate = set[0] == '!';
					if (negate) set = set[1..];
					bool hit = @ok(set.index_of_char(text[t]));
					return hit != negate && self.at(p + close + 1, t + 1);
				}
			}
			return t < text.len && text[t] == '[' && self.at(p + 1, t + 1);
		case '\\':
			if (p + 1 < pat.len) return t < text.len && text[t] == pat[p + 1] && self.at(p + 2, t + 1);
			nextcase default;
		default:
			return t < text.len && text[t] == c && self.at(p + 1, t + 1);
	}
}
