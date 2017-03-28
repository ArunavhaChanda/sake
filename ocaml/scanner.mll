{ open Parser }

let spc = [' ' '\t']
let cap = ['A'-'Z']
let low = ['a'-'z']
let ltr = (cap | low)
let dgt = ['0'-'9']
let aln = (ltr | dgt)

rule token = parse
    spc { token lexbuf }
  | "(~" { comment lexbuf }
  | "~" { line_comment lexbuf }
  | '.' { DOT }
  | '_' { UNDER }
  | '|' { BAR }
  | '?' { QUESMARK }
  | '\n'     { NLINE }
  | '('      { LPAREN }
  | ')'      { RPAREN }
  | '{'      { LBRACE }
  | '}'      { RBRACE }
  | '['      { LSQUARE }
  | ']'      { RSQUARE }
  | ';'      { SEMI }
  | ','      { COMMA }
  | '+'      { ADD }
  | '-'      { SUB }
  | '*'      { MUL }
  | '/'      { DIV }
  | '='      { ASSIGN }
  | '"'      { QUOTES }
  | "=="     { EQ }
  | "!="     { NEQ }
  | '<'      { LT }
  | "<="     { LE }
  | ">"      { GT }
  | ">="     { GE }
  | "&&"     { AND }
  | "||"     { OR }
  | "!"      { NOT }
  | "if"     { IF }
  | "else"   { ELSE }
  | "for"    { FOR }
  | "in"     { IN }
  | "while"  { WHILE }
  | "return" { RETURN }
  | "continue"   { CONTINUE }
  | "break"   { BREAK }
  | "int"    { INT }
  | "bool"   { BOOL }
  | "void"   { VOID }
  | "char"   { CHAR }
  | "string"   { STRING }
  | "true"   { TRUE }
  | "false"  { FALSE }
  | "print" { PRINT }
  | "fsm" { FSM }
  | "tick"   { TICK }
  | "reset"   { RESET }
  | "type" { TYPE }
  | "goto" { GOTO }
  | "switch" { SWITCH }
  | "case" { CASE }
  | "goto" { GOTO }
  | "state" { STATE }
  | "start" { START }
  | "input" { INPUT }
  | "output" { OUTPUT }
  | "sysin" { SYSIN }
  | cap aln*  as lxm { TYPENAME (lxm) }
  | low aln* as lxm { ID (lxm) }
  | dgt+ as num { INTLIT (int_of_string num) }
(*
  | dgt+ as lxm { INTLIT(int_of_string lxm) }
  | cap axn* as lxm { ENUM(lxm) }
  | low aln* as lxm { VARIABLE(lxm) }
  *)
  | eof { EOF }
  | _ as char { raise (Failure("illegal character " ^ Char.escaped char)) }

and comment = parse
    "~)" { token lexbuf }
  | _    { comment lexbuf }
and line_comment = parse
    '\n' { token lexbuf }
  | _    { line_comment lexbuf }
