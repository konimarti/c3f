# c3f

A fast, token-based formatter for [C3](https://c3-lang.org).

- **Token-based.** It works on tokens, not a grammar, so half-typed code and new syntax do not stop it.
- **Fast.** The whole standard library in 0.14 s, and in 0.37 s wrapped at 120 columns.

- **Stable.** Formatting twice gives the same bytes: no flapping in CI, no fights with format-on-save.
- **Verified.** Every result is lexed again and compared, token by token, with your code.

- **Stdlib style.** Spacing rules learned from the C3 standard library itself.
- **Optimal wrapping.** Line breaks are determined by a dynamic programming algorithm ([Yelland](https://github.com/google/rfmt/blob/master/inst/doc/A%20New%20Approach%20to%20Optimal%20Code%20Formatting.pdf), as in Google's rfmt). Opt-in.

Format on save, `.editorconfig`, presets, import sorting and a git hook are included.

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

The C3 standard library of c3c 0.8.6 (74faaa9, 365 files), each formatter with its default
settings, and c3f once more wrapping at 120 columns (c3fmt's default limit). Both built from their
git HEAD with `-O3`: c3f b357cb4, [c3fmt](https://github.com/lmichaudel/c3fmt) a53fe85 (v0.3.5).
4 cores (AMD EPYC 9355P).

| | c3f | c3f, 120 columns | c3fmt |
|---|---|---|---|
| Time (median of 5 runs) | 0.14 s | 0.37 s | 3.05 s ¹ |
| Peak memory | 13 MB | 19 MB | 29 MB |
| Lines changed | 1,845 | 2,906 | 14,122 |
| Lines over 120 columns left (1,331 before) | 1,331 | 315 ² | 503 |
| Files whose code changed ³ | 0 | 0 | 9 |
| Files that change again on a second run | 0 | 0 | 31 |
| ... and still on a third run | 0 | 0 | 5 |
| c3c's unit tests (1,878) still pass afterwards | yes | yes | yes |
| Formats a file with a syntax error (e.g. while typing) | yes | yes | no ⁴ |

¹ The same when pinned to one core.<br>
² Mostly comments, contract text and long strings; also one-line blocks, aligned rows and lines with several statements.<br>
³ Differences that remain after removing all whitespace from both files.<br>
⁴ Test file: an unclosed `(` in an `if`. c3fmt leaves a file as it is and reports
`SOURCE_CODE_CONTAINS_ERROR` (exit status 0); from stdin, as editors call it, it stops with
that error unhandled (exit status 132). c3f formats up to the `(`, keeps the rest as written and
names the line on stderr.

c3fmt's own stdlib snapshot (364 files) gives the same picture. *Lines changed* counts the lines
of the input that were changed or removed. [c3tools](https://github.com/alexveden/c3tools) c3fmt
(32b5f03) no longer builds with c3c 0.8.6. To run the comparison yourself:
`tools/bench.py --c3fmt <path to c3fmt>` (`--help` for the options).

## Install

Download a binary for Linux, macOS or Windows from the [releases](https://github.com/konimarti/c3f/releases).
Or build and install it with [c3c](https://github.com/c3lang/c3c) 0.8.5 or later:

```sh
git clone --recurse-submodules https://github.com/konimarti/c3f && make -C c3f install PREFIX=$HOME/.local
```

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
changes, 2 usage or I/O error, 3 `--check` found a place it kept as written (`man c3f` has the details).

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

Helix 25.07 or later (`languages.toml`):

```toml
[[language]]
name = "c3"
formatter = { command = "c3f", args = ["--stdin-filename", "%{buffer_name}", "-"] }
auto-format = true
```

VS Code: install the C3 extension, set `c3.format.path` to the full path of c3f and turn on
`editor.formatOnSave` for `[c3]` ([`contrib/vscode/settings.json`](contrib/vscode/settings.json)).
The extension calls `c3f --stdin --stdout --stdin-filepath=<file>`, which c3f accepts for this
purpose. With a custom path it still compares the `--version` of the binary with the latest
c3fmt release and may offer "New version of c3fmt available"; *Ignore* is enough, the configured
path stays in use.

JetBrains IDEs: run `c3f -w $FilePath$` as an External Tool, or as a File Watcher for format on
save; [`contrib/intellij.editorconfig`](contrib/intellij.editorconfig) gives the C3 plugin's style.

**CI.** Fail the build if anything is not formatted:

```yaml
- run: c3f --check .
```

**Git hook.** `c3f --git-hook` installs a pre-commit hook that refuses commits whose staged C3 files
are not formatted ([`contrib/pre-commit`](contrib/pre-commit)). An existing hook is left as it is.

## Configure

Options come from `.editorconfig` (the nearest file wins) and `--set key=value`:

```ini
[*.{c3,c3i}]
c3f_style = strict            # stdlib (default), knr or strict
indent_style = tab
max_line_length = 100
c3f_line_breaks = wrap        # break the lines over the limit (reflow: lay multi-line statements out again)
```

| Option | What it does |
|---|---|
| `c3f_style` | `stdlib` (default): tabs, Allman braces, the standard library's spacing. `knr`: K&R braces. `strict`: one form where the stdlib itself varies (`Foo* p`, `{ 1, 2 }`, `s[a:b]`), and sorted imports. |
| `max_line_length`, `c3f_line_breaks` | `keep` (default) never moves your line breaks; `wrap` breaks only the statements with a line over the limit; `reflow` also lays out multi-line statements again; `wrap_rewrite` is `wrap` plus two changes that add tokens: a string that is still too long is split into `"a " "b"`, which the compiler joins, and a braceless `if`/`else`/`while`/`for`/`foreach` body that is too long for its line gets `{ }` and its own line (c3c does not allow the body of an `if` on the line after it). The joined value and the added braces are checked. |
| `indent_style`, `indent_size`, `tab_width` | `tab`, 4, 4. |
| `c3f_sort_imports` | `off`, `lines`, `lists`, `all`, `split` (one module per `import`). |
| `c3f_align`, `c3f_align_comments` | `keep` leaves alignment of declarations and trailing comments as written; `decls` and `always` apply it; `off` removes it. |

All options and their values are in the man page: `man c3f` (source: [`c3f.1.scd`](c3f.1.scd)).

## License

MIT, see [LICENSE](LICENSE).
