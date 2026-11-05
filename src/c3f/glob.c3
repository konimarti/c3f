module c3f;

<*
 Glob matching as in .editorconfig: `*` (not across '/'), `**`, `?`, `[abc]`, `[!abc]`,
 `{a,b,c}`.
*>
fn bool glob_match(String pattern, String text)
{
	if (pattern.len == 0) return text.len == 0;
	char c = pattern[0];
	switch (c)
	{
		case '*':
			bool deep = pattern.len > 1 && pattern[1] == '*';
			String rest = pattern[(deep ? 2 : 1)..];
			for (sz k = 0; k <= text.len; k++)
			{
				if (glob_match(rest, text[k..])) return true;
				if (k < text.len && text[k] == '/' && !deep) return false;
			}
			return false;
		case '?':
			return text.len > 0 && text[0] != '/' && glob_match(pattern[1..], text[1..]);
		case '[':
			if (try close = pattern.index_of_char(']'))
			{
				if (close > 1 && text.len > 0)
				{
					String set = pattern[1:close - 1];
					bool negate = set[0] == '!';
					if (negate) set = set[1..];
					bool hit = @ok(set.index_of_char(text[0]));
					return hit != negate && glob_match(pattern[close + 1..], text[1..]);
				}
			}
			return text.len > 0 && text[0] == '[' && glob_match(pattern[1..], text[1..]);
		case '{':
			if (try close = pattern.index_of_char('}'))
			{
				String rest = pattern[close + 1..];
				String alts = pattern[1:close - 1];
				sz from = 0;
				for (sz k = 0; k <= alts.len; k++)
				{
					if (k < alts.len && alts[k] != ',') continue;
					if (glob_match(alts[from:k - from].tconcat(rest), text)) return true;
					from = k + 1;
				}
				return false;
			}
			nextcase default;
		case '\\':
			if (pattern.len > 1) return text.len > 0 && text[0] == pattern[1] && glob_match(pattern[2..], text[1..]);
			nextcase default;
		default:
			return text.len > 0 && text[0] == c && glob_match(pattern[1..], text[1..]);
	}
}
