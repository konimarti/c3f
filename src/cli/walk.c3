module c3f::cli;
import std::io, std::io::path, std::collections::list, std::sort;

fn bool is_source(String p) => p.ends_with(".c3") || p.ends_with(".c3i") || p.ends_with(".c3t");

<* A directory component that is skipped by default: hidden, build output, dependencies. *>
fn bool skipped_dir(String name) => name.starts_with(".") || name == "build" || name == "lib";

<*
 Does an --exclude glob match path `rel` (relative to the directory given on the command line)?
 A glob matches the path or any part of it that starts after a '/', as in .gitignore:
 `gen/*` skips `gen/a.c3` and `src/gen/a.c3`, and `*.g.c3` skips such files anywhere.
*>
fn bool excluded(String rel, List{String}* excludes)
{
	while (rel.starts_with("./")) rel = rel[2..];
	foreach (g : *excludes)
	{
		if (c3f::glob_match(g, rel)) return true;
		foreach (i, c : rel) if (c == '/' && c3f::glob_match(g, rel[i + 1..])) return true;
	}
	return false;
}

<*
 Expand a command line path into source files (directories recursively, sorted). A directory
 that cannot be read is reported and skipped; returns false if anything was.
*>
fn bool collect(List{String}* files, String arg, List{String}* excludes) => walk(files, arg, "", excludes);

fn bool walk(List{String}* files, String dir, String rel, List{String}* excludes) @local
{
	if (!file::is_dir(dir))
	{
		if (!file::exists(dir))
		{
			io::eprintfn("c3f: %s: no such file or directory", dir);
			return false;
		}
		if (!excluded(dir, excludes)) files.push(dir);
		return true;
	}
	PathList? entries = list_dir(dir);
	if (catch entries)
	{
		io::eprintfn("c3f: %s: cannot read the directory", dir);
		return false;
	}
	List{String} names;
	names.tinit();
	foreach (e : entries) names.push((String)e);
	sort::mergesort(&names, fn int(String a, String b) => a.compare_to(b));
	bool ok = true;
	foreach (name : names)
	{
		String full = dir.ends_with("/") ? dir.tconcat(name) : string::tformat("%s/%s", dir, name);
		String sub = rel.len ? string::tformat("%s/%s", rel, name) : name;
		if (excluded(sub, excludes)) continue;
		if (file::is_dir(full))
		{
			// a linked directory is not followed (it can loop, or lead out of the tree)
			if (!skipped_dir(name) && !is_link(full)) ok &= walk(files, full, sub, excludes);
		}
		else if (is_source(name))
		{
			files.push(full);
		}
	}
	return ok;
}

fn PathList? list_dir(String dir) @local => path::ls(tmem, path::tnew(dir)!);

fn bool is_link(String p) @local
{
	if (try pp = path::tnew(p)) return path::is_link(pp);
	return false;
}
