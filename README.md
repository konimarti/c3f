# c3f

A faithful formatter for [C3](https://c3-lang.org).

- **Stdlib style.** c3f writes code in the style of the C3 standard library: its spacing
  rules are learned from the standard library itself, so formatted code reads like the
  stdlib, and the rules can be regenerated as the stdlib evolves.
- **Optimal wrapping.** With a line limit set, c3f lays out each statement with the
  dynamic-programming algorithm of [A New Approach to Optimal Code Formatting](https://github.com/google/rfmt/blob/master/inst/doc/A%20New%20Approach%20to%20Optimal%20Code%20Formatting.pdf)
  (Yelland, the algorithm of Google's rfmt): it weighs every way to break the statement
  against a layout cost, instead of filling one line after the other.
- **Format on save, even mid-edit.** c3f reads tokens, not a C3 grammar, so half-written
  code, syntax errors and new syntax do not stop it: the code inside an unclosed bracket is
  left as written, the rest of the file is formatted, and a note names the line. Setups for
  Vim, Neovim and Helix are below.
- **Fast.** c3f formats the whole standard library in 0.13 s, and in 0.32 s while wrapping
  it at 120 columns, where c3fmt takes 2.4 s. Its time grows in step with the size of a
  file: a table of 4,000 numbers takes 3 ms.

Also: `.editorconfig` support, import sorting, alignment that survives re-indentation,
and format-on-save, CI and git-hook integration.

## How it compares

Formatting the C3 standard library (364 files), with every tool built with `-O3` and
wrapping at 120 columns: c3fmt by default, c3tools with `--width=120 --indent=t` (as its
README suggests for the stdlib), and c3f with `max_line_length = 120` and
`c3f_line_breaks = long` (wrap the lines over the limit, with the optimal layout). c3f's
default, which does not wrap, is shown too. c3f runs on one thread; c3fmt starts one per
core (28 here).

| | c3f | c3f, 120 columns | [c3fmt](https://github.com/lmichaudel/c3fmt) | [c3tools](https://github.com/alexveden/c3tools) c3fmt |
|---|---|---|---|---|
| Time (median of 5 runs) | 0.13 s | 0.32 s | 2.4 s ⁴ | 99 s ² |
| Peak memory | 9 MB | 16 MB | 78 MB | 17 MB |
| Lines changed | 1,842 | 2,905 | 14,069 | 14,854 |
| Lines over 120 columns left (1,329 before) | 1,325 | 305 ³ | 522 | 738 |
| Files whose code or comments changed | 0 ¹ | 0 ¹ | 77 | 110 |
| Files that change again on a second run | 0 | 0 | 31 | 5 |
| Files it fails on | 0 | 0 | 0 | 69 |
| c3c's unit tests still pass afterwards | yes | yes | yes | no (does not compile) |
| Formats a file with a syntax error (e.g. while typing) | yes | yes | no | no |

¹ Two files have multi-line comments whose inner lines moved along with the comment's
indentation; their text is otherwise unchanged.

² Nearly all of it on the 69 files it fails on, each about 1.4 s before it stops; the
others take a few milliseconds each.

³ Mostly comments, contract text and long strings (213); then what c3f keeps on one line:
statements with a comment inside (38), one-line blocks and bodies (29), aligned rows (17).

⁴ The same on one core: c3fmt's threads each format a file while holding its output lock,
so files are formatted one at a time.

## Install

Download a binary for Linux, macOS or Windows from the
[releases](https://github.com/konimarti/c3f/releases), or build it; that needs
[c3c](https://github.com/c3lang/c3c) 0.8.6 and [c3l](https://github.com/konimarti/c3l):

```sh
git clone https://github.com/konimarti/c3f && cd c3f
c3l sync
c3c build c3f        # → build/c3f
```

## Use

```sh
c3f file.c3                # print the formatted file
c3f -w src/                # format files and directories in place
c3f --check src/           # list files that would change (exit 1 if any)
c3f --diff src/            # show the changes as a unified diff
c3f - < file.c3            # stdin → stdout (--stdin-filename for the config lookup)
c3f --print-config file.c3 # the options in effect, and where they come from
c3f -w --exclude 'gen/*' .  # skip paths matching a glob (repeatable)
```

`// c3f off` … `// c3f on` leaves a region untouched. Exit status: 0 ok, 1 `--check`
found changes, 2 usage or I/O error, 3 a place was kept as written (with `-w`, `--check`
or `--diff`; printing the result succeeds, with the notes on stderr). In directories,
hidden ones and those named `build` or `lib` are skipped.

## Format on save, in CI, before every commit

**Editors.** Pipe the buffer through `c3f --stdin-filename <path> -`: the formatted file
comes out on stdout, notes (such as an unclosed bracket) on stderr, and the path is used to
find `.editorconfig`. For example, Vim (`~/.vim/after/ftplugin/c3.vim`, or your `.vimrc`);
the buffer is only replaced if c3f succeeds, and the notes are shown as warnings:

```vim
function! C3fFormat() abort
	let l:err = tempname()
	let l:out = systemlist('c3f --stdin-filename ' . shellescape(expand('%')) . ' - 2>' . shellescape(l:err), getline(1, '$'))
	if v:shell_error == 0 && l:out !=# getline(1, '$')
		let l:view = winsaveview()
		call setline(1, l:out)
		silent! execute (len(l:out) + 1) . ',$delete _'
		call winrestview(l:view)
	endif
	for l:msg in readfile(l:err)
		echohl WarningMsg | echomsg l:msg | echohl None
	endfor
	call delete(l:err)
endfunction
autocmd BufWritePre *.c3,*.c3i call C3fFormat()
```

Feeling bold? `:%!c3f -` formats the buffer in one go, but it replaces the buffer with
whatever c3f prints, notes and error messages included (`u` undoes it).

Neovim with [conform.nvim](https://github.com/stevearc/conform.nvim):

```lua
require("conform").setup({
	formatters = { c3f = { command = "c3f", args = { "--stdin-filename", "$FILENAME", "-" } } },
	formatters_by_ft = { c3 = { "c3f" } },
	format_on_save = { timeout_ms = 500 },
})
```

or Helix (`languages.toml`):

```toml
[[language]]
name = "c3"
formatter = { command = "c3f", args = ["-"] }
auto-format = true
```

**CI.** Fail the build if anything is not formatted:

```yaml
- run: c3f --check .
```

**Git hook.** Run `c3f --git-hook` inside a repository to install a pre-commit hook that
refuses commits whose staged C3 files are not formatted ([`contrib/pre-commit`](contrib/pre-commit)).
An existing hook is left as it is.

## Configure

Options are read from `.editorconfig` (nearest file wins, `root = true` stops the
search) and can be overridden with `--set key=value`:

```ini
[*.c3]
c3f_style = stdlib            # or knr, strict
indent_style = tab
max_line_length = 100
c3f_line_breaks = long        # wrap only lines longer than max_line_length (or: fit)
c3f_sort_imports = lines
```

`c3f_style` picks a preset; the options below then change single settings:

- `stdlib` (default): the standard library's style: tabs, Allman braces, `else` on its own line.
- `knr`: `stdlib` with K&R braces and `} else {`.
- `strict`: `stdlib` with spacing made uniform even where the stdlib varies, `Foo* p`, no
  padding inside brackets, and tight slices `s[a:b]`.

**stdlib or strict?** Both format everything: indentation, braces, blank lines and the spacing
between tokens (`a=b+c` → `a = b + c`, `if(x)` → `if (x)`, `foo( a ,b )` → `foo(a, b)`). The
difference is in the few places where the standard library itself writes both forms, such as
`Foo* p` and `Foo *p`, `[1, 2]` and `[ 1, 2 ]`, `s[a:b]` and `s[a : b]`: about 0.2% of the
spacing in the stdlib. There `stdlib` keeps what you wrote, since either form is stdlib style;
`strict` always writes the more common one.

| Option | Values (default first) |
|---|---|
| `indent_style`, `indent_size`, `tab_width` | `tab`, 4, 4 |
| `end_of_line`, `insert_final_newline` | keep the file's, `true` |
| `max_line_length`, `c3f_line_breaks` | `off`; `preserve`, `long`, `fit` |
| `c3f_wrap_solver` | `dp` (optimal), `search` |
| `c3f_brace_style`, `c3f_else_style` | `allman`, `knr`, `linux` (function bodies Allman, the rest K&R); `follow`, `own_line`, `cuddle` |
| `c3f_one_line_blocks` | `keep`, `expand` |
| `c3f_case_indent`, `c3f_ct_indent` | `indent`, `flush`; `keep`, `indent`, `flush` |
| `c3f_continuation` | `keep`, `tab`, `align` |
| `c3f_spacing` | `stdlib`, `strict` |
| `c3f_space_after_cast`, `c3f_pointer_style`, `c3f_bracket_padding` | `false`; `keep`, `type`, `name`; `keep`, `none`, `space` |
| `c3f_max_blank_lines`, `c3f_trim_block_blanks`, `c3f_decl_spacing` | 2; `true`; `keep`, `1` |
| `c3f_align`, `c3f_align_comments` | `preserve`, `decls` (names, `=` and `=>` of consecutive lines), `off`; `preserve`, `always`, `off` |
| `c3f_trailing_comment_spaces` | `keep`, or the number of spaces before a trailing `//` comment |
| `c3f_magic_comma` | `true` (a trailing comma keeps one item per line when wrapping) |
| `c3f_wrap_cost_hard`, `c3f_wrap_cost_break` | wrapping costs: 100 per column past `max_line_length`, 2 per line break |
| `c3f_soft_max_line_length`, `c3f_wrap_cost_soft` | a second, soft limit (off), and 0.05 per column past it |
| `c3f_wrap_budget` | 2000: statements of more tokens are not wrapped |
| `c3f_sort_imports` | `off`, `lines`, `lists`, `all` |

## License

MIT, see [LICENSE](LICENSE).
