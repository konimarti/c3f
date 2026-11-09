C3F(1)

# NAME

*c3f* - a stable, fast, token-based formatter for C3

# SYNOPSIS

*c3f* [_OPTIONS_] [_PATH_ ...]++
*c3f* [_OPTIONS_] *-*

# DESCRIPTION

*c3f* formats C3 source files and checks every result by lexing it again and comparing it,
token by token, with the input. A place it cannot verify, or that is unbalanced (a bracket
still being typed), is kept as written, so it is safe to run on a file while editing it.

With one file and none of *-w*, *--check* and *--diff*, the formatted file is written to
standard output. With *-*, standard input is read and the result written to standard output.
For directories, every file ending in _.c3_, _.c3i_ and _.c3t_ below them is formatted;
hidden directories and those named _build_ or _lib_ are skipped, and links are not followed
(a file named on the command line is). Files are replaced atomically.

The code between the comments *// c3f off* and *// c3f on* is left untouched.

# OPTIONS

*-w*, *--write*
	Rewrite the files in place.

*--check*
	Write nothing; list the files that would change.

*--diff*
	Print a unified diff of the changes.

*--config* _file_
	Use this _.editorconfig_ instead of searching upward from each file.

*--set* _key_=_value_
	Set an option (see *CONFIGURATION*); repeatable, applied after _.editorconfig_.

*--print-config*
	Print the options in effect for the file and where each comes from.

*--stdin-filename* _path_
	With *-*, the path used to find _.editorconfig_ and in messages.

*--exclude* _glob_
	Skip matching paths; repeatable. A glob is matched against the path below the directory
	given, and against each part of it that starts after a _/_: _gen/\*_ skips
	_src/gen/a.c3_ as well.

*--git-hook*
	Install a pre-commit hook in this git repository that rejects commits with unformatted
	C3 files. An existing hook is kept.

*-h*, *--help*
	Print the usage.

*--version*
	Print the version.

# CONFIGURATION

Options are read from _.editorconfig_ files: the nearest file wins, and _root = true_ stops
the search. The standard keys (*indent_style*, *indent_size*, *tab_width*, *end_of_line*,
*insert_final_newline*, *max_line_length*) are used as they are, and the keys beginning with
_c3f\__ are c3f's own. For example:

```
[*.{c3,c3i}]
indent_style = tab
max_line_length = 100
c3f_line_breaks = wrap
```

Values are given with their default first.

*c3f_style* = stdlib | knr | strict
	A preset, applied before the other options, which override it. *stdlib* is the style of
	the C3 standard library. *knr* uses K&R braces, also for functions, and *} else {*.
	*strict* is *stdlib* with the spacing made uniform where the standard library itself
	varies: _Foo\* p_, padded initializer braces, tight slices, and sorted imports.

*indent_style* = tab | space
	Indent with tabs or spaces.

*indent_size* = 4
	1 to 16, or _tab_ (the value of *tab_width*). The width of one level with spaces.

*tab_width* = 4
	1 to 16. The width of a tab, for aligning and for the line length.

*end_of_line* = keep | lf | crlf
	The line ending. *keep* uses the file's own.

*insert_final_newline* = true | false
	End the file with a line break.

*max_line_length* = off
	*off*, or 1 to 10000. The column limit used by wrapping and alignment.

*c3f_line_breaks* = preserve | wrap | wrap_fit | reflow
	What *c3f* may do with line breaks. It needs a *max_line_length*. *preserve* never
	moves them; *wrap* breaks the statements that have a line over the limit; *reflow*
	also lays out again every statement that spans several lines, so a break made by hand
	is joined if the statement fits on one line. A statement on one line that fits is
	never touched. *wrap_fit* is *wrap*, and in addition:
	- a string literal that still runs past the limit is written as several literals,
	which the compiler joins: "a b c" becomes "a " "b c". It cuts after a space if it can,
	never inside an escape sequence, a UTF-8 character or a *printf* conversion, and not in
	an attribute, an *assert* or a compile-time directive. The value of every piece is
	checked to be the original's.
	- the single statement after an *if*, *else*, *while*, *for* or *foreach* without braces
	that is too long for its line gets braces and a line of its own (*c3c* does not accept the
	statement of an *if* on the line after it, so it could only be broken inside). Bodies that
	start with another *if*, a loop, a *switch* or a *defer* are left as they are.
	Only this option changes more than whitespace. (*wrap-fit* is accepted too.)

*c3f_brace_style* = allman | knr | linux
	Where the opening brace goes. *linux* is *knr* with the braces of functions on their
	own line.

*c3f_else_style* = follow | own_line | cuddle
	Where *else* goes: *follow* the brace style, on its own line, or after *}*.

*c3f_one_line_blocks* = keep | expand
	Keep a block written on one line, or put its statements on lines of their own. *expand* also
	breaks the line after every *;* that ends a statement (not in the header of a *for* or *$for*,
	and not before a comment), and after the *}* of a block. In a compile-time block the header,
	*$else* and *$endif* (and the other end keywords) stand alone on their lines; the body of a
	*$case* or *case* on the line of its label stays, as does a single *if (x) return;*. A
	multi-line initializer starts its elements on the line after its *{*, and its *}* goes on a
	line of its own after a trailing comma; an initializer on one line is not touched.
	The body of a *struct*, *union*, *enum*, *constdef*, *bitstruct* or *interface* written on
	one line is written on several, one member or enum value per line, and so is a *faultdef*
	with more than one member. The braces of an empty body are placed as the brace style says
	(Allman: *fn void f()* and *{}* on the next line; K&R: *{}* on the line); the *{}* stays
	together, and a lambda keeps its braces where they are.

*c3f_case_indent* = indent | flush
	Indent *case* under *switch*, or put it in the same column.

*c3f_ct_indent* = keep | indent | flush
	The contents of *$if*, *$switch* and *$foreach* blocks: as written, indented, or at the
	level of the directive.

*c3f_continuation* = keep | tab | align
	How the lines of a broken statement are continued: as written, one more level, or
	aligned under the opening bracket.

*c3f_spacing* = stdlib | strict
	Where the standard library writes both forms (about 0.2% of its spacing), *stdlib*
	keeps what was written and *strict* always writes the more common one.

*c3f_space_after_cast* = false | true
	A space after a cast: _(int)x_ or _(int) x_.

*c3f_pointer_style* = keep | type | name
	Write _Foo\* p_ (*type*) or _Foo \*p_ (*name*).

*c3f_bracket_padding* = keep | none | space
	Spaces inside _[ ]_ and _( )_.

*c3f_max_blank_lines* = 2
	0 to 100. More blank lines in a row are cut to this number.

*c3f_max_blank_lines_declarations* = common | 0 to 100++
*c3f_max_blank_lines_code* = common | 0 to 100++
*c3f_max_blank_lines_before_rbrace* = common | 0 to 100
	Separate limits for the blank lines between declarations (at the top level and in the body
	of a *struct*, *enum*, ...), in code (a function body, a block, an initializer) and before
	a closing brace of a block or a type body. *common* is *c3f_max_blank_lines*. The limit
	before a closing brace replaces *c3f_trim_block_blanks* there.

*c3f_trim_block_blanks* = true | false
	Remove blank lines after an opening and before a closing brace.

*c3f_decl_spacing* = keep | 1
	*1* puts exactly one blank line between declarations.

*c3f_align* = preserve | decls | off
	Align the names, _=_ and _=>_ of consecutive lines (*decls*), keep the alignment as
	written (*preserve*), or remove it (*off*).

*c3f_align_comments* = preserve | always | off
	The same for trailing comments.

*c3f_trailing_comment_spaces* = keep
	*keep*, or 1 to 16. The spaces before a trailing _//_ comment.

*c3f_magic_comma* = true | false
	A trailing comma keeps one item per line when wrapping.

*c3f_soft_max_line_length* = 0
	0 (off) to 10000. A second, soft limit for wrapping.

*c3f_wrap_cost_hard* = 100
	The cost of a column past *max_line_length*.

*c3f_wrap_cost_soft* = 0.05
	The cost of a column past *c3f_soft_max_line_length*.

*c3f_wrap_cost_break* = 2
	The cost of a line break.

*c3f_wrap_budget* = 2000
	0 to 10000. Statements of more tokens are not wrapped.

*c3f_sort_imports* = off | lines | lists | all | split
	Reorder imports. *lines* sorts the statements of a run (no blank line between them),
	*lists* the modules inside one statement, *all* both, and *split* also writes one module
	per statement (a statement with a comment is only sorted). The *strict* style uses
	*all*; an explicit value wins.

# EXIT STATUS

*0*
	Success.

*1*
	*--check* found files that would change.

*2*
	Usage or I/O error.

*3*
	A place was kept as written (with *-w* or *--check*). Printing the result or the diff
	succeeds, with the notes on standard error.

# EXAMPLES

Format a project in place:

```
c3f -w src/
```

Fail a CI job if anything is not formatted:

```
c3f --check .
```

Format in an editor, with the path used for _.editorconfig_:

```
c3f --stdin-filename src/main.c3 -
```

# FILES

_.editorconfig_
	The options, found by searching upward from each file.

# SEE ALSO

*c3c*(1), https://editorconfig.org

# AUTHOR

c3f was written by Koni Marti <koni.marti@gmail.com>.
