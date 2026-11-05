# c3f

A faithful formatter for [C3](https://c3-lang.org).

- **Stdlib style.** c3f writes code in the style of the C3 standard library: its spacing
  rules are learned from the standard library itself, so formatted code reads like the
  stdlib, and the rules can be regenerated as the stdlib evolves.
- **Optimal wrapping.** With a line limit set, c3f lays out each statement with the
  dynamic-programming algorithm of [A New Approach to Optimal Code Formatting](https://github.com/google/rfmt/blob/master/inst/doc/A%20New%20Approach%20to%20Optimal%20Code%20Formatting.pdf)
  (Yelland, the algorithm of Google's rfmt): it weighs every way to break the statement
  against a layout cost, instead of filling one line after the other.
- **Future-proof.** c3f does not depend on a C3 grammar, so new or unfinished syntax does
  not stop it: that part is left as written and the rest of the file is formatted.
- **Fast.** c3f formats the whole standard library in under 0.2 s.

Also: `.editorconfig` support, import sorting, alignment that survives re-indentation,
and format-on-save, CI and git-hook integration.

## How it compares

Formatting the C3 standard library (364 files) with each tool's default settings
(c3tools: `--width=120 --indent=t`, as its README suggests for the stdlib):

| | c3f | [c3fmt](https://github.com/lmichaudel/c3fmt) | [c3tools](https://github.com/alexveden/c3tools) c3fmt |
|---|---|---|---|
| Time (median of 5 runs) | 0.17 s | 2.5 s | 88 s |
| Peak memory | 9 MB | 91 MB | 15 MB |
| Lines changed | 1,804 | 14,069 | 14,854 |
| Files whose code or comments changed | 0 ¹ | 77 | 110 |
| Files that change again on a second run | 0 | 31 | 5 |
| Files it fails on | 0 | 0 | 69 |
| c3c's unit tests still pass afterwards | yes | yes | no (does not compile) |

¹ Two files have multi-line comments whose inner lines moved along with the comment's
indentation; their text is otherwise unchanged.

## Install

Needs [c3c](https://github.com/c3lang/c3c) 0.8.6 and [c3l](https://github.com/konimarti/c3l):

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
```

`// c3f off` … `// c3f on` leaves a region untouched. Exit status: 0 ok, 1 `--check`
found changes, 2 usage or I/O error, 3 a place was kept as written. In
directories, hidden ones and those named `build` or `lib` are skipped.

## Format on save, in CI, before every commit

**Editors.** Pipe the buffer through `c3f --stdin-filename <path> -`: the formatted file
comes out on stdout, and the path is used to find `.editorconfig`. For example, Vim
(`~/.vim/after/ftplugin/c3.vim`, or your `.vimrc`); the buffer is only replaced if c3f
succeeds:

```vim
function! C3fFormat() abort
	let l:out = systemlist('c3f --stdin-filename ' . shellescape(expand('%')) . ' -', getline(1, '$'))
	if (v:shell_error == 0 || v:shell_error == 3) && l:out !=# getline(1, '$')
		let l:view = winsaveview()
		call setline(1, l:out)
		silent! execute (len(l:out) + 1) . ',$delete _'
		call winrestview(l:view)
	endif
endfunction
autocmd BufWritePre *.c3,*.c3i call C3fFormat()
```

Feeling bold? `:%!c3f -` formats the buffer in one go, but it replaces the buffer with
whatever c3f prints, error messages included (`u` undoes it).

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
| `c3f_sort_imports` | `off`, `lines`, `lists`, `all` |

## License

MIT, see [LICENSE](LICENSE).
