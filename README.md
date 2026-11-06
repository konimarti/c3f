# c3f

A fast, verified formatter for [C3](https://c3-lang.org). By default it changes only whitespace, and proves it (the opt-in `wrap_fit` also adds braces and splits strings).

- **Verified.** Every result is lexed again and compared, token by token, with your original.
  Anything that differs is kept as written, so your code is never changed.
- **Stable.** Formatting twice gives the same bytes: no flapping in CI, no fights with format-on-save.
- **Stdlib style.** Spacing rules learned from the C3 standard library itself.
- **Fast.** The whole standard library in 0.13 s, and in 0.30 s wrapped at 120 columns with an
  optimal layout ([Yelland](https://github.com/google/rfmt/blob/master/inst/doc/A%20New%20Approach%20to%20Optimal%20Code%20Formatting.pdf), as in Google's rfmt).

It works on tokens, not a grammar, so half-typed code and new syntax do not stop it. Format on save,
`.editorconfig`, presets, import sorting and a git hook are included.

With `max_line_length = 72` and `c3f_line_breaks = wrap`,

```c3
fn void main(){
  int[] primes={2,3,5,7,11};
  foreach(i,p:primes){
      if(p>5&&i%2==0)io::printfn("prime %d at %d",p,i);
      total+=compute_weight(p,i,primes.len)*scale_factor_for(category,p);
  }
}
```

becomes

```c3
fn void main()
{
	int[] primes = {2, 3, 5, 7, 11};
	foreach (i, p : primes)
	{
		if (p > 5 && i % 2 == 0) io::printfn("prime %d at %d", p, i);
		total += compute_weight(p, i, primes.len)
			* scale_factor_for(category, p);
	}
}
```

## How it compares

The C3 standard library (364 files), every tool built with `-O3` and wrapping at 120 columns.
c3f runs on one thread; c3fmt uses all 28 cores. Versions: c3fmt c74d563, c3tools 32b5f03,
standard library c23910038 (0.8.6).

| | c3f | c3f, 120 columns | [c3fmt](https://github.com/lmichaudel/c3fmt) | [c3tools](https://github.com/alexveden/c3tools) c3fmt |
|---|---|---|---|---|
| Time (median of 5 runs) | 0.13 s | 0.30 s | 2.4 s ⁴ | 99 s ² |
| Peak memory | 10 MB | 17 MB | 78 MB | 17 MB |
| Lines changed | 1,858 | 2,910 | 14,069 | 14,854 |
| Lines over 120 columns left (1,329 before) | 1,325 | 317 ³ | 522 | 738 |
| Files whose code or comments changed | 0 ¹ | 0 ¹ | 77 | 110 |
| Files that change again on a second run | 0 | 0 | 31 | 5 |
| Files it fails on | 0 | 0 | 0 | 69 |
| c3c's unit tests still pass afterwards | yes | yes | yes | no (does not compile) |
| Formats a file with a syntax error (e.g. while typing) | yes | yes | no | no |

¹ Two files: the indentation of the inner lines of multi-line comments moved with the comment.<br>
² Nearly all on the 69 files it fails on, about 1.4 s each.<br>
³ Mostly comments, contract text and long strings; also one-line blocks, aligned rows and lines with several statements.<br>
⁴ The same on one core.

The C3 plugin for IntelliJ and CLion ([c3lang/c3intellij](https://github.com/c3lang/c3intellij))
formats inside the IDE, so it is not in the table. The default styles largely agree; c3f also works
in any editor, in CI and in a git hook, reads `.editorconfig`, wraps to a column limit and sorts imports.

## Install

Download a binary for Linux, macOS or Windows from the
[releases](https://github.com/konimarti/c3f/releases), or build it with
[c3c](https://github.com/c3lang/c3c) 0.8.5 or later and [c3l](https://github.com/konimarti/c3l):

```sh
git clone https://github.com/konimarti/c3f && cd c3f
c3l sync
c3c build c3f        # → build/c3f
```

`make install` builds and installs `c3f` and its man page (`PREFIX`, `DESTDIR`).

## Use

```sh
c3f file.c3                # print the formatted file
c3f -w src/                # format files and directories in place
c3f --check src/           # list files that would change (exit 1 if any)
c3f --diff src/            # show the changes as a unified diff
c3f - < file.c3            # stdin → stdout (--stdin-filename for the config lookup)
c3f --print-config file.c3 # the options in effect, and where they come from
c3f -w --exclude 'gen/*' .  # skip paths matching a glob
```

`// c3f off` … `// c3f on` leaves a region untouched. Exit status: 0 ok, 1 `--check` found
changes, 2 usage or I/O error, 3 a place was kept as written (`man c3f` has the details).

## Format on save, in CI, before every commit

**Editors.** Pipe the buffer through `c3f --stdin-filename <path> -`: the formatted file comes
out on stdout, notes (such as an unclosed bracket) on stderr. Vim (`.vimrc`); the buffer is only
replaced if c3f succeeds, and the notes are shown as warnings:

```vim
function! C3fFormat() abort
	let l:err = tempname()
	let l:out = systemlist('c3f --stdin-filename ' . shellescape(expand('%')) . ' - 2>' . shellescape(l:err), getline(1, '$'))
	if v:shell_error == 0 && l:out !=# getline(1, '$')
		let l:view = winsaveview()
		call setline(1, l:out)
		if len(l:out) < line('$') | silent execute (len(l:out) + 1) . ',$delete _' | endif
		call winrestview(l:view)
	endif
	for l:msg in readfile(l:err)
		echohl WarningMsg | echomsg l:msg | echohl None
	endfor
	call delete(l:err)
endfunction
autocmd BufWritePre *.c3,*.c3i call C3fFormat()
```

Neovim with [conform.nvim](https://github.com/stevearc/conform.nvim):

```lua
require("conform").setup({
	formatters = { c3f = { command = "c3f", args = { "--stdin-filename", "$FILENAME", "-" } } },
	formatters_by_ft = { c3 = { "c3f" } },
	format_on_save = { timeout_ms = 500 },
})
```

Helix (`languages.toml`):

```toml
[[language]]
name = "c3"
formatter = { command = "c3f", args = ["-"] }
auto-format = true
```

JetBrains IDEs (IntelliJ IDEA, CLion, ...): add an external tool (*Settings | Tools | External
Tools*) with Program the full path of `c3f`, Arguments `-w $FilePath$`, Working directory `$FileDir$`
and *Synchronize files after execution* ticked. For format on save use the *File Watchers* plugin
(IntelliJ IDEA: Ultimate) with the C3 file type, Program `c3f-save`, Arguments `$FilePath$`, and
*Trigger the watcher regardless of syntax errors* ticked. The IDE disables a watcher whose program
fails, and `c3f -w` exits with 3 when it keeps a place as written, so `c3f-save` (on your PATH) maps that to 0:

```sh
#!/bin/sh
c3f -w "$1"
case $? in 0|3) exit 0 ;; *) exit 1 ;; esac
```

**CI.** Fail the build if anything is not formatted:

```yaml
- run: c3f --check .
```

**Git hook.** `c3f --git-hook` installs a pre-commit hook that refuses commits whose staged C3 files
are not formatted ([`contrib/pre-commit`](contrib/pre-commit)). An existing hook is left as it is.

## Configure

Options come from `.editorconfig` (the nearest file wins) and `--set key=value`:

```ini
[*.c3]
c3f_style = strict            # stdlib (default), knr or strict
indent_style = tab
max_line_length = 100
c3f_line_breaks = wrap        # break the lines over the limit (reflow: lay multi-line statements out again)
```

| Option | What it does |
|---|---|
| `c3f_style` | `stdlib` (default): tabs, Allman braces, the standard library's spacing. `knr`: K&R braces. `strict`: one form where the stdlib itself varies (`Foo* p`, `{ 1, 2 }`, `s[a:b]`), and sorted imports. |
| `max_line_length`, `c3f_line_breaks` | `preserve` (default) never moves your line breaks; `wrap` breaks only the statements with a line over the limit; `reflow` also lays out multi-line statements again; `wrap_fit` is `wrap` plus two changes that add tokens: a string that is still too long is split into `"a " "b"`, which the compiler joins, and a braceless `if`/`else`/`while`/`for`/`foreach` body that is too long for its line gets `{ }` and its own line (c3c does not allow the body of an `if` on the line after it). The joined value and the added braces are checked. |
| `indent_style`, `indent_size`, `tab_width` | `tab`, 4, 4. |
| `c3f_sort_imports` | `off`, `lines`, `lists`, `all`, `split` (one module per `import`). |
| `c3f_align`, `c3f_align_comments` | Keep (`preserve`), apply (`decls`, `always`) or remove (`off`) alignment of declarations and trailing comments. |

All options and their values are in the man page: `man c3f` (source: [`c3f.1.scd`](c3f.1.scd)).

## License

MIT, see [LICENSE](LICENSE).
