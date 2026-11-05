module c3f::cli;
import c3f, std::io, std::io::path, std::collections::list, libc;

const String VERSION = "0.1.0";

enum Status : int { OK, CHANGED, ERROR, KEPT }

fn Status worst(Status a, Status b)
{
	if (a == ERROR || b == ERROR) return ERROR;
	if (a == KEPT || b == KEPT) return KEPT;
	return a == CHANGED || b == CHANGED ? Status.CHANGED : Status.OK;
}

fn int main(String[] args)
{
	Options opt;
	if (catch opt.parse(args)) return Status.ERROR.ordinal;
	if (opt.help)
	{
		io::printn(HELP);
		return 0;
	}
	if (opt.version)
	{
		io::printfn("c3f %s", VERSION);
		return 0;
	}
	if (opt.git_hook) return install_git_hook().ordinal;
	if (opt.stdin) return run_stdin(&opt).ordinal;
	if (!opt.paths.len())
	{
		io::eprintn("c3f: no input (give paths, or '-' for stdin; see c3f --help)");
		return Status.ERROR.ordinal;
	}
	List{String} files;
	bool listed = true;   // false: a path could not be listed (reported; the others are still done)
	foreach (p : opt.paths) listed &= c3f::cli::collect(&files, p, &opt.excludes);
	if (!files.len())
	{
		if (!listed) return Status.ERROR.ordinal;
		io::eprintn("c3f: no C3 files (*.c3, *.c3i, *.c3t) found");
		return opt.mode == STDOUT ? Status.ERROR.ordinal : Status.OK.ordinal;
	}
	bool one = opt.paths.len() == 1 && files.len() == 1 && !file::is_dir(opt.paths[0]);
	if (opt.mode == STDOUT && !one)
	{
		io::eprintn("c3f: several files: use -w, --check or --diff");
		return Status.ERROR.ordinal;
	}
	Status status = listed ? Status.OK : Status.ERROR;
	foreach (f : files)
	{
		@pool()
		{
			status = worst(status, run_file(&opt, f));
		};
	}
	return status.ordinal;
}

fn c3f::Config? config_for(Options* opt, String path)
{
	String error;
	c3f::Config? cfg = c3f::load_config(path, opt.config, opt.sets.array_view(), &error);
	if (catch err = cfg)
	{
		io::eprintfn("c3f: %s", error);
		return err~;
	}
	return cfg;
}

fn Status run_stdin(Options* opt)
{
	String name = opt.stdin_filename ?: "<stdin>";
	c3f::Config? cfg = config_for(opt, opt.stdin_filename ?: "stdin.c3");
	if (catch cfg) return ERROR;
	if (opt.mode == PRINT_CONFIG)
	{
		print_config(name, &cfg);
		return OK;
	}
	DString d;
	d.tinit();
	if (catch d.read_from_stream(io::stdin()))
	{
		io::eprintn("c3f: cannot read stdin");
		return ERROR;
	}
	return run(opt, name, d.str_view(), &cfg);
}

fn Status run_file(Options* opt, String path)
{
	c3f::Config? cfg = config_for(opt, path);
	if (catch cfg) return ERROR;
	if (opt.mode == PRINT_CONFIG)
	{
		print_config(path, &cfg);
		return OK;
	}
	char[]? data = file::load_temp(path);
	if (catch data)
	{
		io::eprintfn("c3f: %s: cannot read", path);
		return ERROR;
	}
	return run(opt, path, (String)data, &cfg);
}

<*
 Format one input and act on the mode (-w is only given with files: stdin is printed).
 A place kept as written is exit status 3 for --check and -w; printing the result or the diff
 is a success (the notes go to stderr), so format-on-save works on code in progress.
*>
fn Status run(Options* opt, String name, String src, c3f::Config* cfg)
{
	c3f::FormatResult r = c3f::format(tmem, src, cfg);
	Status s = report(name, &r);
	switch (opt.mode)
	{
		case CHECK:
			if (r.changed) io::printn(name);
			return worst(s, r.changed ? Status.CHANGED : Status.OK);
		case DIFF:
			if (r.changed) io::print(c3f::unified_diff(tmem, name, src, r.text));
			return OK;
		case WRITE:
			if (r.changed && !write_atomic(name, r.text)) return ERROR;
		default:
			// printed (for an editor: the whole file; the notes went to stderr)
			io::print(r.text);
			return OK;
	}
	return s;
}

fn Status report(String name, c3f::FormatResult* r)
{
	if (r.fallback)
	{
		foreach (n : r.notes) io::eprintfn("%s:%d: %s", name, n.line, n.text);
	}
	return r.fallback ? Status.KEPT : Status.OK;
}

extern fn CInt chmod(ZString path, libc::Mode_t mode) @feat(POSIX);
extern fn CInt access(ZString path, CInt mode) @feat(POSIX);

<*
 Write through a temporary file that takes the original's permissions, then rename it over
 the original. A symbolic link is written through in place, so the link stays a link.
*>
fn bool write_atomic(String path, String text)
{
	bool link = @ok(path::tnew(path)) && path::is_link(path::tnew(path)!!);
	if (link)
	{
		if (catch file::save(path, text))
		{
			io::eprintfn("c3f: %s: cannot write", path);
			return false;
		}
		return true;
	}
	$if env::POSIX:
		// the rename below would replace a read-only file: refuse, as writing to it would
		if (access(path.zstr_tcopy(), 2 /* W_OK */) != 0)
		{
			io::eprintfn("c3f: %s: not writable", path);
			return false;
		}
	$endif
	String tmp = path.tconcat(".c3f~");
	if (catch file::save(tmp, text))
	{
		io::eprintfn("c3f: %s: cannot write", tmp);
		(void)file::delete(tmp);
		return false;
	}
	$if env::POSIX:
		libc::Stat st;
		if (libc::stat(path.zstr_tcopy(), &st) == 0) (void)chmod(tmp.zstr_tcopy(), st.st_mode & 0o7777);
	$endif
	bool renamed = libc::rename(tmp.zstr_tcopy(), path.zstr_tcopy()) == 0;
	$if env::WIN32:
		// Windows does not rename over an existing file: remove it first
		if (!renamed && @ok(file::delete(path))) renamed = libc::rename(tmp.zstr_tcopy(), path.zstr_tcopy()) == 0;
	$endif
	if (!renamed)
	{
		io::eprintfn("c3f: %s: cannot replace", path);
		(void)file::delete(tmp);
		return false;
	}
	return true;
}

fn void print_config(String name, c3f::Config* cfg)
{
	io::printfn("# %s", name);
	foreach (k : c3f::Key::values)
	{
		io::printfn("%-26s = %-10s (%s)", k.name, cfg.value_text(k), cfg.origin[k.ordinal]);
	}
}
