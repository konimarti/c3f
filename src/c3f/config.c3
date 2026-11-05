module c3f;
import std::io, std::collections::list;

faultdef UNKNOWN_KEY, BAD_VALUE;

enum IndentStyle : char { TAB, SPACE }
enum Eol : char { KEEP, LF, CRLF }
enum BraceStyle : char { ALLMAN, KNR, LINUX }   // LINUX: function bodies Allman, everything else K&R
enum ElseStyle : char { FOLLOW, OWN_LINE, CUDDLE }
enum OneLineBlocks : char { KEEP, EXPAND }
enum Continuation : char { KEEP, TAB, ALIGN }
enum SpacingMode : char { STDLIB, STRICT }
enum PointerStyle : char { KEEP, TYPE, NAME }
enum BracketPadding : char { KEEP, NONE, SPACE }
enum DeclSpacing : char { KEEP, ONE }
enum AlignMode : char { PRESERVE, DECLS, OFF }
enum CommentAlign : char { PRESERVE, ALWAYS, OFF }
enum LineBreaks : char { PRESERVE, LONG, FIT }
enum WrapSolver : char { DP, SEARCH }
enum SortImports : char { OFF, LINES, LISTS, ALL }
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
	bool           trim_block_blanks;
	DeclSpacing    decl_spacing;
	AlignMode      align;
	CommentAlign   align_comments;
	sz             trailing_comment_spaces;  // before a trailing // comment; 0 = keep
	LineBreaks     line_breaks;
	WrapSolver     wrap_solver;
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
	TRIM_BLOCK_BLANKS    { "c3f_trim_block_blanks" },
	DECL_SPACING         { "c3f_decl_spacing" },
	ALIGN                { "c3f_align" },
	ALIGN_COMMENTS       { "c3f_align_comments" },
	TRAILING_COMMENT_SPACES { "c3f_trailing_comment_spaces" },
	LINE_BREAKS          { "c3f_line_breaks" },
	WRAP_SOLVER          { "c3f_wrap_solver" },
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
		.max_blank_lines = 2, .trim_block_blanks = true, .decl_spacing = KEEP,
		.align = PRESERVE, .align_comments = PRESERVE,
		.line_breaks = PRESERVE, .wrap_solver = DP, .magic_comma = true,
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
		self.bracket_padding = NONE;
		self.origin[Key.SPACING.ordinal] = from;
		self.origin[Key.POINTER_STYLE.ordinal] = from;
		self.origin[Key.BRACKET_PADDING.ordinal] = from;
	}
	self.origin[Key.STYLE.ordinal] = origin;
	return true;
}

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

macro sz? parse_uint(String v) => (sz)(v.to_uint() ?? BAD_VALUE~!);

macro float? parse_float(String v)
{
	double d = v.to_double() ?? BAD_VALUE~!;
	if (d < 0) return BAD_VALUE~;
	return (float)d;
}

macro parse_enum($Type, String v)
{
	$Type? r = BAD_VALUE~;
	foreach (e : $Type::values)
	{
		if (string::tformat("%s", e).to_lower_tcopy() == v)
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
		case MAX_LINE_LENGTH: self.max_line_length = v == "off" ? 0 : parse_uint(v)!;
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
		case MAX_BLANK_LINES: self.max_blank_lines = parse_uint(v)!;
		case TRIM_BLOCK_BLANKS: self.trim_block_blanks = parse_bool(v)!;
		case DECL_SPACING: self.decl_spacing = v == "1" ? ONE : parse_enum(DeclSpacing, v)!;
		case ALIGN: self.align = parse_enum(AlignMode, v)!;
		case ALIGN_COMMENTS: self.align_comments = parse_enum(CommentAlign, v)!;
		case TRAILING_COMMENT_SPACES:
			self.trailing_comment_spaces = v == "keep" ? 0 : parse_uint(v)!;
			if (self.trailing_comment_spaces > 16) return BAD_VALUE~;
		case LINE_BREAKS: self.line_breaks = parse_enum(LineBreaks, v)!;
		case WRAP_SOLVER: self.wrap_solver = parse_enum(WrapSolver, v)!;
		case MAGIC_COMMA: self.magic_comma = parse_bool(v)!;
		case SOFT_MAX_LINE_LENGTH: self.soft_max_line_length = parse_uint(v)!;
		case WRAP_COST_SOFT: self.wrap_cost_soft = parse_float(v)!;
		case WRAP_COST_HARD: self.wrap_cost_hard = parse_float(v)!;
		case WRAP_COST_BREAK: self.wrap_cost_break = parse_float(v)!;
		case WRAP_BUDGET: self.wrap_budget = parse_uint(v)!;
		case SORT_IMPORTS: self.sort_imports = parse_enum(SortImports, v)!;
	}
	self.origin[k.ordinal] = origin;
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
		case TRIM_BLOCK_BLANKS: return bool_text(self.trim_block_blanks);
		case DECL_SPACING: return self.decl_spacing == ONE ? "1" : "keep";
		case ALIGN: return enum_text(self.align);
		case ALIGN_COMMENTS: return enum_text(self.align_comments);
		case TRAILING_COMMENT_SPACES: return self.trailing_comment_spaces ? string::tformat("%d", self.trailing_comment_spaces) : "keep";
		case LINE_BREAKS: return enum_text(self.line_breaks);
		case WRAP_SOLVER: return enum_text(self.wrap_solver);
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
