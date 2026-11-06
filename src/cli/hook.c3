module c3f::cli;
import std::io, std::io::path, std::os::process, std::os::env, libc;

// the pre-commit hook, built into the binary
const char[*] HOOK = $embed("../../contrib/pre-commit");

faultdef NOT_A_REPOSITORY;

<* The top directory of the git repository containing the current directory. *>
fn String? git_root()
{
	String dir = c3f::absolute(".");
	while (true)
	{
		if (file::exists(c3f::join_path(dir, ".git"))) return dir;
		if (c3f::is_root(dir)) return NOT_A_REPOSITORY~;
		dir = c3f::parent_dir(dir);
	}
}

<* The hooks directory of the repository at `root` (a checkout, a worktree or a submodule). *>
fn String? hooks_dir(String root)
{
	String dot_git = c3f::join_path(root, ".git");
	if (file::is_dir(dot_git)) return dot_git.tconcat("/hooks");
	// a worktree or submodule: ".git" is a file "gitdir: <path>"
	String line = ((String)file::load_temp(dot_git)!).trim();
	if (!line.starts_with("gitdir:")) return NOT_A_REPOSITORY~;
	String dir = line[7..].trim();
	if (!c3f::path_root(dir.treplace("\\", "/")).len) dir = c3f::join_path(root, dir);
	dir = c3f::absolute(dir);
	// a worktree shares the hooks of the main repository
	String common = dir.tconcat("/commondir");
	if (file::exists(common))
	{
		String c = ((String)file::load_temp(common)!).trim();
		dir = c3f::absolute(c3f::path_root(c.treplace("\\", "/")).len ? c : c3f::join_path(dir, c));
	}
	return dir.tconcat("/hooks");
}

<* `core.hooksPath` of the repository at `root`, made absolute, or "" if it is not set (or git cannot be run). *>
fn String configured_hooks(String root)
{
	char[4096] buf;
	String? out = process::run_capture_stdout(&buf, { "git", "-C", root, "config", "--get", "core.hooksPath" }, INHERIT_ENV);
	if (catch out) return "";
	String dir = out.trim();
	if (!dir.len) return "";
	if (dir.starts_with("~/")) dir = c3f::join_path(env::get_home_dir(tmem) ?? "~", dir[2..]);
	if (!c3f::path_root(dir.treplace("\\", "/")).len) dir = c3f::join_path(root, dir);
	return c3f::absolute(dir.tcopy());
}

<* --git-hook: install the pre-commit hook in the current git repository; an existing hook is never replaced. *>
fn Status install_git_hook()
{
	String? root = git_root();
	if (catch root)
	{
		io::eprintn("c3f: not inside a git repository");
		return ERROR;
	}
	String? hooks = hooks_dir(root);
	if (catch hooks)
	{
		io::eprintfn("c3f: %s/.git: not a git directory", root);
		return ERROR;
	}
	// git runs the hooks from core.hooksPath when it is set
	String configured = configured_hooks(root);
	if (configured.len) hooks = configured;
	String dest = hooks.tconcat("/pre-commit");
	if (file::exists(dest))
	{
		char[]? old = file::load_temp(dest);
		if (try old && (String)old == (String)&HOOK)
		{
			io::eprintfn("c3f: warning: the hook is already installed in %s", dest);
			return OK;
		}
		io::eprintfn("c3f: warning: %s already exists and was left as it is; to add the check to it, see", dest);
		io::eprintn("    https://github.com/konimarti/c3f/blob/main/contrib/pre-commit");
		return OK;
	}
	if (!file::is_dir(hooks)) (void)path::mkdir(path::tnew(hooks)!!, true);
	if (catch save_checked(dest, &HOOK))
	{
		io::eprintfn("c3f: %s: cannot write", dest);
		return ERROR;
	}
	$if env::POSIX:
		(void)chmod(dest.zstr_tcopy(), 0o755);
	$endif
	io::printfn("c3f: installed %s", dest);
	return OK;
}
