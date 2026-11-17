module c3f::cli;
import c3f, libc, std::collections::list, std::io, std::io::path, std::time;

const String VERSION = env::PROJECT_VERSION;

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
 A place kept as written is exit status 3 for --check only; -w, printing the result and the
 diff succeed (the notes go to stderr), so format-on-save works on code in progress.
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
			if (r.changed && !print_out(c3f::unified_diff(tmem, name, src, r.text))) return ERROR;
			return OK;
		case WRITE:
			if (r.changed && !write_atomic(name, r.text)) return ERROR;
			return OK;
		default:
			// printed (for an editor: the whole file; the notes went to stderr)
			return print_out(r.text) ? Status.OK : Status.ERROR;
	}
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
extern fn CInt move_file_ex(WString from, WString to, CUInt flags) @cname("MoveFileExW") @feat(WIN32);
const CUInt MOVEFILE_REPLACE_EXISTING = 1;
const CUInt MOVEFILE_WRITE_THROUGH = 8;

<*
 Write through a temporary file that takes the original's permissions, then rename it over
 the original. A symbolic link is written through in place, so the link stays a link, and so is
 a file with other hard links: a new file would leave them with the old text.
*>
fn bool write_atomic(String path, String text)
{
	bool link = @ok(path::tnew(path)) && path::is_link(path::tnew(path)!!);
	$if env::POSIX:
		libc::Stat st;
		bool have_stat = libc::stat(path.zstr_tcopy(), &st) == 0;
		if (have_stat && st.st_nlink > 1) link = true;
	$endif
	if (link)
	{
		if (catch save_checked(path, text))
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
	String? tmp = save_new(path, text);
	if (catch tmp)
	{
		io::eprintfn("c3f: %s: cannot write a temporary file", path);
		return false;
	}
	$if env::POSIX:
		if (have_stat) (void)chmod(tmp.zstr_tcopy(), st.st_mode & 0o7777);
	$endif
	$if env::WIN32:
		// in one step, with UTF-16 paths: rename reads them in the ANSI code page and does not
		// replace a file (deleting it first could lose both when the rename then fails)
		WString? from = tmp.to_temp_wstring();
		WString? to = path.to_temp_wstring();
		bool renamed = @ok(from) && @ok(to) && move_file_ex(from!!, to!!, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) != 0;
	$else
		bool renamed = libc::rename(tmp.zstr_tcopy(), path.zstr_tcopy()) == 0;
	$endif
	if (!renamed)
	{
		io::eprintfn("c3f: %s: cannot replace", path);
		(void)file::delete(tmp);
		return false;
	}
	return true;
}

<*
 Write the text to a new file next to `path` and return its name. The file is created exclusively
 (a file or a link that is already there is never written through), under a name made for the
 purpose; a taken name is skipped.
*>
fn String? save_new(String path, String text)
{
	ulong seed = (ulong)time::now();
	// (a short name of its own in the same directory: the file's own name may leave no room for a suffix)
	sz dir_len;
	foreach (i, c : path)
	{
		bool separator = c == '/';
		// (a backslash is a part of a name elsewhere)
		$if env::WIN32:
			separator = separator || c == '\\';
		$endif
		if (separator) dir_len = i + 1;
	}
	String dir = path[:dir_len];
	for (int attempt = 0; attempt < 100; attempt++)
	{
		String tmp = string::tformat("%s.c3f-%x-%d~", dir, seed, attempt);
		File? f = file::open(tmp, "wbx");
		if (catch f) continue;
		if (catch err = write_closed(&f, text))
		{
			(void)file::delete(tmp);
			return err~;
		}
		return tmp.copy(tmem);
	}
	return io::ALREADY_EXISTS~;
}

<*
 Write a file and report every error: file::save ignores the result of closing it, and that is
 where the end of the text is written (a full disk then left a cut file, and success).
*>
fn void? save_checked(String path, char[] data)
{
	File f = file::open(path, "wb")!;
	write_closed(&f, data)!;
}

<* Write all of the data to an open file and close it, reporting the error of either. *>
fn void? write_closed(File* f, char[] data)
{
	defer (void)f.close();
	io::write_all(f, data)!;
	f.close()!;
}

<* Print to stdout: false (and a message) if it could not be written, e.g. on a full disk. *>
fn bool print_out(String text)
{
	File* out = io::stdout();
	// (File.flush drops the result of fflush, which is where a full disk shows)
	if (try out.write(text) && libc::fflush(out.file) == 0) return true;
	io::eprintn("c3f: cannot write the output");
	return false;
}

fn void print_config(String name, c3f::Config* cfg)
{
	io::printfn("# %s", name);
	io::printn("# To use these options as an .editorconfig, save them in a file named .editorconfig in the");
	io::printn("# project root, starting with these lines:");
	io::printn("#   root = true");
	io::printn("#   [*.c3]");
	io::printn("# Then keep each option and its value, and drop the text in parentheses (where it comes from).");
	foreach (k : c3f::Key::values)
	{
		io::printfn("%-26s = %-10s (%s)", k.name, cfg.value_text(k), cfg.origin[k.ordinal]);
	}
}
