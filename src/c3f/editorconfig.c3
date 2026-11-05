module c3f;
import std::io, std::io::path, std::collections::list, std::core::ascii;

faultdef BAD_CONFIG;

struct Setting
{
	String key;
	String value;
	String origin;     // file:line
}

<* The root part of an absolute path: "/" or a drive "C:/" ("" if relative). Paths use '/'. *>
fn String path_root(String p)
{
	if (p.starts_with("/")) return "/";
	if (p.len >= 3 && p[1] == ':' && p[2] == '/' && ascii::is_alpha(p[0])) return p[:3];
	return "";
}

fn bool is_root(String p) => p.len && path_root(p) == p;

fn String parent_dir(String p)
{
	if (is_root(p)) return p;
	if (try i = p.rindex_of_char('/'))
	{
		String root = path_root(p);
		return i < root.len ? root : p[:i];
	}
	return ".";
}

<* `dir` + "/" + name, without doubling the '/' of a root. *>
fn String join_path(String dir, String name) => dir.ends_with("/") ? dir.tconcat(name) : string::tformat("%s/%s", dir, name);

<* Absolute path with `.` and `..` resolved (so the .editorconfig search walks real ancestors). *>
fn String absolute(String p)
{
	p = p.treplace("\\", "/");   // Windows separators
	if (!path_root(p).len)
	{
		Path? cwd = path::tcwd();
		if (catch cwd) return p;
		p = join_path(((String)cwd).treplace("\\", "/"), p);
	}
	String root = path_root(p);
	List{String} parts;
	parts.tinit();
	foreach (part : p[root.len..].tsplit("/"))
	{
		switch (part)
		{
			case "": case ".": break;
			case "..": if (parts.len()) (void)parts.pop();
			default: parts.push(part);
		}
	}
	DString d;
	d.tinit();
	d.append(root);
	foreach (i, part : parts)
	{
		if (i > 0) d.append("/");
		d.append(part);
	}
	return d.len() ? d.str_view() : "/";
}

<* Does a section header match `file` (absolute), for a .editorconfig in `dir`? *>
fn bool section_matches(String section, String dir, String file)
{
	if (section.contains("/"))
	{
		String rel = file.starts_with(dir) ? file[dir.len..] : file;
		if (rel.starts_with("/")) rel = rel[1..];
		return glob_match(section.starts_with("/") ? section[1..] : section, rel);
	}
	String base = file;
	if (try i = file.rindex_of_char('/')) base = file[i + 1..];
	return glob_match(section, base);
}

<*
 Read one .editorconfig and append the settings whose section matches `file`.
 @return "true if the file says root = true"
*>
fn bool? read_editorconfig(String config_path, String file, List{Setting}* out, String* error)
{
	char[]? data = file::load_temp(config_path);
	if (catch data)
	{
		*error = string::tformat("%s: cannot read", config_path);
		return BAD_CONFIG~;
	}
	String dir = parent_dir(absolute(config_path));
	bool root;
	bool in_preamble = true;
	bool matches;
	sz line_no;
	foreach (raw : ((String)data).tsplit("\n"))
	{
		line_no++;
		String line = raw.trim();
		if (line.len == 0 || line[0] == '#' || line[0] == ';') continue;
		if (line[0] == '[')
		{
			if (!line.ends_with("]"))
			{
				*error = string::tformat("%s:%d: bad section header", config_path, line_no);
				return BAD_CONFIG~;
			}
			in_preamble = false;
			matches = section_matches(line[1:line.len - 2], dir, file);
			continue;
		}
		sz? eq = line.index_of_char('=');
		if (catch eq)
		{
			*error = string::tformat("%s:%d: expected key = value", config_path, line_no);
			return BAD_CONFIG~;
		}
		String key = line[:eq].trim().to_lower_tcopy();
		String value = strip_comment(line[eq + 1..]).trim();
		if (in_preamble)
		{
			if (key == "root") root = value.to_lower_tcopy() == "true";
			continue;
		}
		if (matches) out.push({key, value, string::tformat("%s:%d", config_path, line_no)});
	}
	return root;
}

fn String strip_comment(String v)
{
	for (sz i = 1; i < v.len; i++)
	{
		if ((v[i] == '#' || v[i] == ';') && (v[i - 1] == ' ' || v[i - 1] == '\t')) return v[:i];
	}
	return v;
}

<*
 The configuration for `file`: defaults, then the preset, then every matching
 .editorconfig section from the outermost file to the nearest, then `sets`
 ("key=value", in order). With `explicit` set, only that .editorconfig is read.
*>
fn Config? load_config(String file, String explicit = "", String[] sets = {}, String* error = null)
{
	String dummy;
	if (!error) error = &dummy;
	String abs = absolute(file);
	List{Setting} settings;
	settings.tinit();
	if (explicit.len)
	{
		read_editorconfig(explicit, abs, &settings, error)!;
	}
	else
	{
		List{String} found;
		found.tinit();
		String dir = parent_dir(abs);
		while (true)
		{
			String candidate = join_path(dir, ".editorconfig");
			if (file::exists(candidate))
			{
				found.push(candidate);
				// root = true stops the search; it is read again below, in order
				List{Setting} probe;
				probe.tinit();
				if (read_editorconfig(candidate, abs, &probe, error)!) break;
			}
			if (is_root(dir) || dir == ".") break;
			dir = parent_dir(dir);
		}
		for (sz k = found.len(); k > 0; k--) read_editorconfig(found[k - 1], abs, &settings, error)!;
	}
	foreach (kv : sets)
	{
		sz? eq = kv.index_of_char('=');
		if (catch eq)
		{
			*error = string::tformat("--set %s: expected key=value", kv);
			return BAD_CONFIG~;
		}
		settings.push({kv[:eq].trim().to_lower_tcopy(), kv[eq + 1..].trim(), "--set"});
	}
	// `unset` takes back everything said about a key before it
	List{Setting} kept;
	kept.tinit();
	foreach (st : settings)
	{
		if (st.value.to_lower_tcopy() != "unset")
		{
			kept.push(st);
			continue;
		}
		for (sz k = kept.len(); k > 0; k--) if (kept[k - 1].key == st.key) kept.remove_at(k - 1);
	}
	settings = kept;
	Config cfg = defaults();
	// the preset applies first, wherever it was set
	foreach (s : settings)
	{
		if (s.key == Key.STYLE.name && !cfg.apply_preset(s.value.to_lower_tcopy(), s.origin))
		{
			*error = string::tformat("%s: c3f_style: unknown preset '%s' (use %s)", s.origin, s.value, allowed_values(STYLE));
			return BAD_CONFIG~;
		}
	}
	foreach (s : settings)
	{
		if (s.key == Key.STYLE.name) continue;
		if (catch err = cfg.set(s.key, s.value, s.origin))
		{
			// in an .editorconfig file, another tool's key or a value c3f does not use is no error
			// (and is not applied); on the command line it is
			if (!s.key.starts_with("c3f_") && s.origin != "--set") continue;
			if (err == UNKNOWN_KEY)
			{
				*error = string::tformat("%s: unknown option '%s'", s.origin, s.key);
			}
			else
			{
				*error = string::tformat("%s: %s: invalid value '%s' (use %s)", s.origin, s.key, s.value, allowed_values(key_from_name(s.key)!!));
			}
			return BAD_CONFIG~;
		}
	}
	cfg.finish();
	return cfg;
}
