module c3f;
import std::collections::list, std::io, std::math;

faultdef UNKNOWN_KEY, BAD_VALUE;

const sz COMMON_LIMIT = 1000;   // a blank-line limit that follows c3f_max_blank_lines

enum IndentStyle : char { TAB, SPACE }
enum Eol : char { KEEP, LF, CRLF }
enum BraceStyle : char { ALLMAN, KNR, LINUX }   // LINUX: function bodies Allman, everything else K&R
enum ElseStyle : char { FOLLOW, OWN_LINE, CUDDLE }
enum OneLineBlocks : char { KEEP, EXPAND }
enum Continuation : char { KEEP, TAB, ALIGN, FLUSH }
enum SpacingMode : char { STDLIB, STRICT }
enum PointerStyle : char { KEEP, TYPE, NAME }
enum BracketPadding : char { KEEP, NONE, SPACE }
enum DeclSpacing : char { KEEP, ONE }
enum AlignMode : char { PRESERVE, DECLS, OFF }
enum CommentAlign : char { PRESERVE, ALWAYS, OFF }
enum CommentSpacing : char { NORMALIZE, KEEP }
enum LineBreaks : char { PRESERVE, WRAP, WRAP_FIT, REFLOW }
enum SortImports : char { OFF, LINES, LISTS, ALL, SPLIT }
enum CtIndent : char { KEEP, INDENT, FLUSH }

struct Config
{
	IndentStyle    indent_style;
	sz             indent_size;
	sz             tab_width;
	Eol            end_of_line;
	bool           insert_final_newline;
	sz             max_line_length;          // 0 = off
	BraceStyle     brace_style;
	ElseStyle      else_style;
	OneLineBlocks  one_line_blocks;
	bool           case_indent;
	CtIndent       ct_indent;
	Continuation   continuation;
	SpacingMode    spacing;
	bool           space_after_cast;
	PointerStyle   pointer_style;
	BracketPadding bracket_padding;
	sz             max_blank_lines;
	sz             blank_lines_declarations;  // COMMON_LIMIT: max_blank_lines
	sz             blank_lines_code;
	sz             blank_lines_before_rbrace;
	bool           trim_block_blanks;
	DeclSpacing    decl_spacing;
	AlignMode      align;
	CommentAlign   align_comments;
	CommentSpacing comment_spacing;
	bool           reindent_comments;       // the inner lines of a multi-line comment move with its first line
	sz             trailing_comment_spaces;  // before a trailing // comment; 0 = keep
	LineBreaks     line_breaks;
	bool           magic_comma;
	sz             soft_max_line_length;     // wrapping: c3f_wrap_cost_soft per character past it (0: every character)
	float          wrap_cost_soft;
	float          wrap_cost_hard;
	float          wrap_cost_break;
	sz             wrap_budget;
	SortImports    sort_imports;
	String         style;                    // the preset last applied
	String[Key::len] origin;                  // where each value came from (--print-config)
}

<* Every option, by its .editorconfig / --set name. *>
enum Key : char (String name)
{
	STYLE                { "c3f_style" },
	INDENT_STYLE         { "indent_style" },
	INDENT_SIZE          { "indent_size" },
	TAB_WIDTH            { "tab_width" },
	END_OF_LINE          { "end_of_line" },
	INSERT_FINAL_NEWLINE { "insert_final_newline" },
	MAX_LINE_LENGTH      { "max_line_length" },
	BRACE_STYLE          { "c3f_brace_style" },
	ELSE_STYLE           { "c3f_else_style" },
	ONE_LINE_BLOCKS      { "c3f_one_line_blocks" },
	CASE_INDENT          { "c3f_case_indent" },
	CT_INDENT            { "c3f_ct_indent" },
	CONTINUATION         { "c3f_continuation" },
	SPACING              { "c3f_spacing" },
	SPACE_AFTER_CAST     { "c3f_space_after_cast" },
	POINTER_STYLE        { "c3f_pointer_style" },
	BRACKET_PADDING      { "c3f_bracket_padding" },
	MAX_BLANK_LINES      { "c3f_max_blank_lines" },
	MAX_BLANK_LINES_DECLARATIONS { "c3f_max_blank_lines_declarations" },
	MAX_BLANK_LINES_CODE { "c3f_max_blank_lines_code" },
	MAX_BLANK_LINES_BEFORE_RBRACE { "c3f_max_blank_lines_before_rbrace" },
	TRIM_BLOCK_BLANKS    { "c3f_trim_block_blanks" },
	DECL_SPACING         { "c3f_decl_spacing" },
	ALIGN                { "c3f_align" },
	ALIGN_COMMENTS       { "c3f_align_comments" },
	COMMENT_SPACING      { "c3f_comment_spacing" },
	REINDENT_COMMENTS    { "c3f_reindent_comments" },
	TRAILING_COMMENT_SPACES { "c3f_trailing_comment_spaces" },
	LINE_BREAKS          { "c3f_line_breaks" },
	MAGIC_COMMA          { "c3f_magic_comma" },
	SOFT_MAX_LINE_LENGTH { "c3f_soft_max_line_length" },
	WRAP_COST_SOFT       { "c3f_wrap_cost_soft" },
	WRAP_COST_HARD       { "c3f_wrap_cost_hard" },
	WRAP_COST_BREAK      { "c3f_wrap_cost_break" },
	WRAP_BUDGET          { "c3f_wrap_budget" },
	SORT_IMPORTS         { "c3f_sort_imports" },
}

<* The style of the C3 standard library. *>
fn Config defaults()
{
	Config c = {
		.indent_style = TAB, .indent_size = 4, .tab_width = 4,
		.end_of_line = KEEP, .insert_final_newline = true,
		.brace_style = ALLMAN, .else_style = FOLLOW, .one_line_blocks = KEEP,
		.case_indent = true, .ct_indent = KEEP, .continuation = KEEP,
		.spacing = STDLIB, .space_after_cast = false, .pointer_style = KEEP, .bracket_padding = KEEP,
		.max_blank_lines = 2, .blank_lines_declarations = COMMON_LIMIT, .blank_lines_code = COMMON_LIMIT,
		.blank_lines_before_rbrace = COMMON_LIMIT, .trim_block_blanks = true, .decl_spacing = KEEP,
		.align = PRESERVE, .align_comments = PRESERVE, .reindent_comments = true,
		.line_breaks = PRESERVE, .magic_comma = true,
		.wrap_cost_soft = 0.05, .wrap_cost_hard = 100, .wrap_cost_break = 2, .wrap_budget = 2000,
		.sort_imports = OFF, .style = "stdlib",
	};
	foreach (&o : c.origin) *o = "default";
	return c;
}

fn Key? key_from_name(String name)
{
	foreach (k : Key::values) if (k.name == name) return k;
	return UNKNOWN_KEY~;
}

<* A preset; returns false if the name is unknown. *>
fn bool Config.apply_preset(&self, String name, String origin)
{
	if (name != "stdlib" && name != "knr" && name != "strict") return false;
	String from = string::tformat("preset %s", name);
	*self = defaults();
	self.style = name;
	if (name == "knr")
	{
		self.brace_style = KNR;
		self.else_style = CUDDLE;
		self.origin[Key.BRACE_STYLE.ordinal] = from;
		self.origin[Key.ELSE_STYLE.ordinal] = from;
	}
	if (name == "strict")
	{
		self.spacing = STRICT;
		self.pointer_style = TYPE;
		self.sort_imports = ALL;
		self.origin[Key.SPACING.ordinal] = from;
		self.origin[Key.POINTER_STYLE.ordinal] = from;
		self.origin[Key.SORT_IMPORTS.ordinal] = from;
	}
	self.origin[Key.STYLE.ordinal] = origin;
	return true;
}

<* `wrap` and `wrap-fit`: only the statements with a line over the limit are broken. *>
fn bool Config.wraps_only(&self) => self.line_breaks == WRAP || self.line_breaks == WRAP_FIT;

<*
 Settle values that depend on each other, as in .editorconfig: `indent_size = tab` uses
 tab_width, and tab_width follows indent_size unless it was set itself.
*>
fn void Config.finish(&self)
{
	bool tab_set = self.origin[Key.TAB_WIDTH.ordinal] != "default";
	bool size_set = self.origin[Key.INDENT_SIZE.ordinal] != "default";
	if (self.indent_size == 0) self.indent_size = self.tab_width;
	if (size_set && !tab_set) self.tab_width = self.indent_size;
}

macro bool? parse_bool(String v)
{
	switch (v)
	{
		case "true": return true;
		case "false": return false;
		default: return BAD_VALUE~;
	}
}

fn sz? parse_limit(String v)
{
	if (v == "common") return COMMON_LIMIT;
	sz n = parse_uint(v)!;
	if (n > 100) return BAD_VALUE~;
	return n;
}

fn String limit_text(sz n) => n == COMMON_LIMIT ? "common" : string::tformat("%d", n);

macro sz? parse_uint(String v) => (sz)(v.to_uint() ?? BAD_VALUE~!);

macro float? parse_float(String v)
{
	double d = v.to_double() ?? BAD_VALUE~!;
	if (!math::is_finite(d) || d < 0) return BAD_VALUE~;
	return (float)d;
}

macro parse_enum($Type, String v)
{
	$Type? r = BAD_VALUE~;
	foreach (e : $Type::values)
	{
		if (enum_text(e) == v.treplace("-", "_"))
		{
			r = e;
			break;
		}
	}
	return r;
}

<*
 Set one option by name. Values are lower case, as in .editorconfig.
 `origin` is recorded for --print-config.
*>
fn void? Config.set(&self, String key, String value, String origin = "--set")
{
	// on a copy: a value that is rejected must not stay in effect
	Config c = *self;
	c.set_value(key, value, origin)!;
	*self = c;
}

fn void? Config.set_value(&self, String key, String value, String origin)
{
	Key k = key_from_name(key)!;
	String v = value.trim().to_lower_tcopy();
	switch (k)
	{
		case STYLE:
			if (!self.apply_preset(v, origin)) return BAD_VALUE~;
			return;
		case INDENT_STYLE: self.indent_style = parse_enum(IndentStyle, v)!;
		case INDENT_SIZE:
			// "tab" (0 here) means tab_width; resolved by finish()
			self.indent_size = v == "tab" ? 0 : parse_uint(v)!;
			if ((self.indent_size == 0 && v != "tab") || self.indent_size > 16) return BAD_VALUE~;
		case TAB_WIDTH:
			self.tab_width = parse_uint(v)!;
			if (self.tab_width == 0 || self.tab_width > 16) return BAD_VALUE~;
		case END_OF_LINE: self.end_of_line = parse_enum(Eol, v)!;
		case INSERT_FINAL_NEWLINE: self.insert_final_newline = parse_bool(v)!;
		case MAX_LINE_LENGTH:
			self.max_line_length = v == "off" ? 0 : parse_uint(v)!;
			if ((self.max_line_length == 0 && v != "off") || self.max_line_length > MAX_COLUMNS) return BAD_VALUE~;
		case BRACE_STYLE: self.brace_style = parse_enum(BraceStyle, v)!;
		case ELSE_STYLE: self.else_style = parse_enum(ElseStyle, v)!;
		case ONE_LINE_BLOCKS: self.one_line_blocks = parse_enum(OneLineBlocks, v)!;
		case CASE_INDENT: self.case_indent = parse_indent(v)!;
		case CT_INDENT: self.ct_indent = parse_enum(CtIndent, v)!;
		case CONTINUATION: self.continuation = parse_enum(Continuation, v)!;
		case SPACING: self.spacing = parse_enum(SpacingMode, v)!;
		case SPACE_AFTER_CAST: self.space_after_cast = parse_bool(v)!;
		case POINTER_STYLE: self.pointer_style = parse_enum(PointerStyle, v)!;
		case BRACKET_PADDING: self.bracket_padding = parse_enum(BracketPadding, v)!;
		case MAX_BLANK_LINES:
			self.max_blank_lines = parse_uint(v)!;
			if (self.max_blank_lines > 100) return BAD_VALUE~;
		case MAX_BLANK_LINES_DECLARATIONS: self.blank_lines_declarations = parse_limit(v)!;
		case MAX_BLANK_LINES_CODE: self.blank_lines_code = parse_limit(v)!;
		case MAX_BLANK_LINES_BEFORE_RBRACE: self.blank_lines_before_rbrace = parse_limit(v)!;
		case TRIM_BLOCK_BLANKS: self.trim_block_blanks = parse_bool(v)!;
		case DECL_SPACING: self.decl_spacing = v == "1" ? ONE : parse_enum(DeclSpacing, v)!;
		case ALIGN: self.align = parse_enum(AlignMode, v)!;
		case ALIGN_COMMENTS: self.align_comments = parse_enum(CommentAlign, v)!;
		case COMMENT_SPACING: self.comment_spacing = parse_enum(CommentSpacing, v)!;
		case REINDENT_COMMENTS: self.reindent_comments = parse_bool(v)!;
		case TRAILING_COMMENT_SPACES:
			self.trailing_comment_spaces = v == "keep" ? 0 : parse_uint(v)!;
			if ((self.trailing_comment_spaces == 0 && v != "keep") || self.trailing_comment_spaces > 16) return BAD_VALUE~;
		case LINE_BREAKS: self.line_breaks = parse_enum(LineBreaks, v)!;
		case MAGIC_COMMA: self.magic_comma = parse_bool(v)!;
		case SOFT_MAX_LINE_LENGTH:
			self.soft_max_line_length = parse_uint(v)!;
			if (self.soft_max_line_length > MAX_COLUMNS) return BAD_VALUE~;
		case WRAP_COST_SOFT: self.wrap_cost_soft = parse_float(v)!;
		case WRAP_COST_HARD: self.wrap_cost_hard = parse_float(v)!;
		case WRAP_COST_BREAK: self.wrap_cost_break = parse_float(v)!;
		case WRAP_BUDGET:
			self.wrap_budget = parse_uint(v)!;
			if (self.wrap_budget > MAX_WRAP_BUDGET) return BAD_VALUE~;
		case SORT_IMPORTS: self.sort_imports = parse_enum(SortImports, v)!;
	}
	self.origin[k.ordinal] = origin;
}

const sz MAX_COLUMNS = 10000;
const sz MAX_WRAP_BUDGET = 10000;

<* The values an option takes, for error messages. *>
fn String allowed_values(Key k)
{
	switch (k)
	{
		case STYLE: return "stdlib, knr, strict";
		case INDENT_STYLE: return enum_names(IndentStyle);
		case INDENT_SIZE: return "1 to 16, or tab";
		case TAB_WIDTH: return "1 to 16";
		case END_OF_LINE: return enum_names(Eol);
		case INSERT_FINAL_NEWLINE: case REINDENT_COMMENTS: case SPACE_AFTER_CAST: case TRIM_BLOCK_BLANKS: case MAGIC_COMMA: return "true, false";
		case MAX_LINE_LENGTH: return "off, or 1 to 10000";
		case BRACE_STYLE: return enum_names(BraceStyle);
		case ELSE_STYLE: return enum_names(ElseStyle);
		case ONE_LINE_BLOCKS: return enum_names(OneLineBlocks);
		case CASE_INDENT: return "indent, flush";
		case CT_INDENT: return enum_names(CtIndent);
		case CONTINUATION: return enum_names(Continuation);
		case SPACING: return enum_names(SpacingMode);
		case POINTER_STYLE: return enum_names(PointerStyle);
		case BRACKET_PADDING: return enum_names(BracketPadding);
		case MAX_BLANK_LINES: return "0 to 100";
		case MAX_BLANK_LINES_DECLARATIONS: case MAX_BLANK_LINES_CODE: case MAX_BLANK_LINES_BEFORE_RBRACE: return "common, 0 to 100";
		case DECL_SPACING: return "keep, 1";
		case ALIGN: return enum_names(AlignMode);
		case ALIGN_COMMENTS: return enum_names(CommentAlign);
		case COMMENT_SPACING: return enum_names(CommentSpacing);
		case TRAILING_COMMENT_SPACES: return "keep, or 1 to 16";
		case LINE_BREAKS: return enum_names(LineBreaks);
		case SOFT_MAX_LINE_LENGTH: return "0 (off) to 10000";
		case WRAP_COST_SOFT: case WRAP_COST_HARD: case WRAP_COST_BREAK: return "a number, 0 or more";
		case WRAP_BUDGET: return "0 to 10000";
		case SORT_IMPORTS: return enum_names(SortImports);
	}
}

macro String enum_names($Type)
{
	DString d;
	d.tinit();
	foreach (i, e : $Type::values)
	{
		if (i) d.append(", ");
		d.append(enum_text(e));
	}
	return d.str_view();
}

macro bool? parse_indent(String v)
{
	switch (v)
	{
		case "indent": return true;
		case "flush": return false;
		default: return BAD_VALUE~;
	}
}

<* The current value of an option, as text (--print-config). *>
fn String Config.value_text(&self, Key k)
{
	switch (k)
	{
		case STYLE: return self.style;
		case INDENT_STYLE: return enum_text(self.indent_style);
		case INDENT_SIZE: return string::tformat("%d", self.indent_size);
		case TAB_WIDTH: return string::tformat("%d", self.tab_width);
		case END_OF_LINE: return enum_text(self.end_of_line);
		case INSERT_FINAL_NEWLINE: return bool_text(self.insert_final_newline);
		case MAX_LINE_LENGTH: return self.max_line_length ? string::tformat("%d", self.max_line_length) : "off";
		case BRACE_STYLE: return enum_text(self.brace_style);
		case ELSE_STYLE: return enum_text(self.else_style);
		case ONE_LINE_BLOCKS: return enum_text(self.one_line_blocks);
		case CASE_INDENT: return self.case_indent ? "indent" : "flush";
		case CT_INDENT: return enum_text(self.ct_indent);
		case CONTINUATION: return enum_text(self.continuation);
		case SPACING: return enum_text(self.spacing);
		case SPACE_AFTER_CAST: return bool_text(self.space_after_cast);
		case POINTER_STYLE: return enum_text(self.pointer_style);
		case BRACKET_PADDING: return enum_text(self.bracket_padding);
		case MAX_BLANK_LINES: return string::tformat("%d", self.max_blank_lines);
		case MAX_BLANK_LINES_DECLARATIONS: return limit_text(self.blank_lines_declarations);
		case MAX_BLANK_LINES_CODE: return limit_text(self.blank_lines_code);
		case MAX_BLANK_LINES_BEFORE_RBRACE: return limit_text(self.blank_lines_before_rbrace);
		case TRIM_BLOCK_BLANKS: return bool_text(self.trim_block_blanks);
		case DECL_SPACING: return self.decl_spacing == ONE ? "1" : "keep";
		case ALIGN: return enum_text(self.align);
		case ALIGN_COMMENTS: return enum_text(self.align_comments);
		case COMMENT_SPACING: return enum_text(self.comment_spacing);
		case REINDENT_COMMENTS: return bool_text(self.reindent_comments);
		case TRAILING_COMMENT_SPACES: return self.trailing_comment_spaces ? string::tformat("%d", self.trailing_comment_spaces) : "keep";
		case LINE_BREAKS: return enum_text(self.line_breaks);
		case MAGIC_COMMA: return bool_text(self.magic_comma);
		case SOFT_MAX_LINE_LENGTH: return string::tformat("%d", self.soft_max_line_length);
		case WRAP_COST_SOFT: return string::tformat("%g", self.wrap_cost_soft);
		case WRAP_COST_HARD: return string::tformat("%g", self.wrap_cost_hard);
		case WRAP_COST_BREAK: return string::tformat("%g", self.wrap_cost_break);
		case WRAP_BUDGET: return string::tformat("%d", self.wrap_budget);
		case SORT_IMPORTS: return enum_text(self.sort_imports);
	}
}

macro String enum_text(e) => string::tformat("%s", e).to_lower_tcopy();
macro String bool_text(bool b) => b ? "true" : "false";
