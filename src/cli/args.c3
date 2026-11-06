module c3f::cli;
import std::collections::list, std::io;

faultdef UNKNOWN_FLAG, MISSING_VALUE, USAGE;

enum Mode : char { STDOUT, WRITE, CHECK, DIFF, PRINT_CONFIG }

struct Options
{
	Mode         mode;
	bool         stdin;
	bool         help;
	bool         version;
	bool         git_hook;
	String       config;          // "" = search upward for .editorconfig
	String       stdin_filename;  // with "-": the path for .editorconfig lookup and messages
	List{String} sets;            // "key=value", applied after .editorconfig, in order
	List{String} excludes;
	List{String} paths;
}

<* Flags may come before or after paths; "--" ends flags, "-" means stdin. *>
fn void? Options.parse(&self, String[] args)
{
	bool flags_done;
	for (sz i = 1; i < args.len; i++)
	{
		String a = args[i];
		if (flags_done || !a.starts_with("-") || a == "-")
		{
			if (a == "-")
			{
				self.stdin = true;
				continue;
			}
			self.paths.push(a);
			continue;
		}
		String value;
		bool has_value;
		if (a.starts_with("--"))
		{
			if (try eq = a.index_of_char('='))
			{
				value = a[eq + 1..];
				a = a[:eq];
				has_value = true;
			}
		}
		switch (a)
		{
			case "--": flags_done = true;
			case "-w": case "--write": self.set_mode(WRITE, a)!;
			case "--check": self.set_mode(CHECK, a)!;
			case "--diff": self.set_mode(DIFF, a)!;
			case "--print-config": self.set_mode(PRINT_CONFIG, a)!;
			case "-h": case "--help": self.help = true;
			case "--version": self.version = true;
			case "--git-hook": self.git_hook = true;
			case "--config": case "--set": case "--stdin-filename": case "--exclude":
				if (!has_value)
				{
					if (++i >= args.len)
					{
						io::eprintfn("c3f: %s needs a value", a);
						return MISSING_VALUE~;
					}
					value = args[i];
				}
				switch (a)
				{
					case "--config": self.config = value;
					case "--set": self.sets.push(value);
					case "--stdin-filename": self.stdin_filename = value;
					default: self.excludes.push(value);
				}
			default:
				io::eprintfn("c3f: unknown flag '%s' (see c3f --help)", a);
				return UNKNOWN_FLAG~;
		}
	}
	if (self.stdin && self.paths.len())
	{
		io::eprintn("c3f: '-' (stdin) cannot be combined with paths");
		return USAGE~;
	}
	if (self.stdin && self.mode == WRITE)
	{
		io::eprintn("c3f: -w writes files; for stdin the result goes to stdout without it");
		return USAGE~;
	}
	if (self.stdin_filename.len && !self.stdin)
	{
		io::eprintn("c3f: --stdin-filename is for '-' (stdin)");
		return USAGE~;
	}
}

<* One of -w, --check, --diff, --print-config; they do not combine. *>
fn void? Options.set_mode(&self, Mode m, String flag)
{
	if (self.mode != STDOUT && self.mode != m)
	{
		io::eprintfn("c3f: %s: only one of -w, --check, --diff and --print-config can be given", flag);
		return USAGE~;
	}
	self.mode = m;
}

const String HELP = `c3f - a fast, verified formatter for C3

usage:
  c3f [flags] [path ...]   format files or directories (*.c3, *.c3i, *.c3t; in directories,
                           hidden ones and those named build or lib are skipped)
  c3f [flags] -            read stdin, write stdout

flags:
  -w, --write              rewrite files in place
      --check              write nothing; list files that would change; exit 1 if any
      --diff               print a unified diff of the changes
      --config <file>      use this .editorconfig instead of searching upward
      --set <key>=<value>  set an option (repeatable); applied after .editorconfig
      --print-config       print the effective options and where they come from
      --stdin-filename <p> with '-': the path used for .editorconfig and messages
      --exclude <glob>     skip matching paths (repeatable)
      --git-hook           install a pre-commit hook in this git repository that rejects
                           commits with unformatted C3 files (an existing hook is kept)
  -h, --help               this help
      --version            print the version

One file without -w, --check or --diff is written to stdout.
Exit status: 0 ok, 1 --check found changes, 2 usage or I/O error, 3 a place was kept as written
(with -w or --check; when printing the result or the diff, the notes go to stderr and the status is 0).`;
