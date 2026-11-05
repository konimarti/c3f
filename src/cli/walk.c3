module c3f::cli;
import std::io, std::io::path, std::collections::list;

fn bool is_source(String p) => p.ends_with(".c3") || p.ends_with(".c3i") || p.ends_with(".c3t");

<* A directory component that is skipped by default: hidden, build output, dependencies. *>
fn bool skipped_dir(String name) => name.starts_with(".") || name == "build" || name == "lib";

fn bool excluded(String p, List{String}* excludes)
{
	while (p.starts_with("./")) p = p[2..];
	foreach (g : *excludes) if (c3f::glob_match(g, p) || c3f::glob_match(g, base_name(p))) return true;
	return false;
}

fn String base_name(String p)
{
	if (try i = p.rindex_of_char('/')) return p[i + 1..];
	return p;
}

<* Expand the command line paths into source files (directories recursively, sorted). *>
fn void? collect(List{String}* files, String arg, List{String}* excludes)
{
	if (!file::is_dir(arg))
	{
		if (!file::exists(arg))
		{
			io::eprintfn("c3f: %s: no such file or directory", arg);
			return io::FILE_NOT_FOUND~;
		}
		if (!excluded(arg, excludes)) files.push(arg);
		return;
	}
	PathList entries = path::ls(tmem, path::tnew(arg)!)!;
	List{String} names;
	names.tinit();
	foreach (e : entries) names.push((String)e);
	sort_strings(&names);
	foreach (name : names)
	{
		String full = arg.ends_with("/") ? arg.tconcat(name) : string::tformat("%s/%s", arg, name);
		if (excluded(full, excludes)) continue;
		if (file::is_dir(full))
		{
			// a linked directory is not followed (it can loop, or lead out of the tree)
			if (!skipped_dir(name) && !path::is_link(path::tnew(full)!)) collect(files, full, excludes)!;
		}
		else if (is_source(name))
		{
			files.push(full);
		}
	}
}

fn void sort_strings(List{String}* l)
{
	// insertion sort: directory listings are short
	for (sz i = 1; i < l.len(); i++)
	{
		String x = (*l)[i];
		sz j = i;
		while (j > 0 && (*l)[j - 1].compare_to(x) > 0)
		{
			(*l)[j] = (*l)[j - 1];
			j--;
		}
		(*l)[j] = x;
	}
}
