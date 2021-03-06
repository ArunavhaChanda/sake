(* 
 * Main semantic checker
 *
 * Author: Arunavha Chanda
 *)

module A = Ast
module S = Sast
open Printf

module StringMap = Map.Make(String)

exception SemanticError of string

let string_of_type = function
  | S.Bool -> "Bool"
  | S.Int -> "Int"
  | S.Char -> "Char"
  | S.String -> "String"
  | _ -> "other"

let rec print_list = function 
  [] -> ()
  | (s,t)::l -> print_string "(" ; print_string s ; print_string "," ; print_string (string_of_type t) ; print_string ")" ; print_string " " ; print_list l

let rec find_variable scope name =
  try List.find (fun (s, _) -> s = name) scope.S.variables
  with Not_found ->
    match scope.parent with
      | Some(parent) -> find_variable parent name
      | _ -> raise Not_found

let require_integer e msg =
  if (e = S.Int) then () else raise (SemanticError msg)

let report_duplicate exceptf list =
  let rec helper = function
    | n1 :: n2 :: _ when n1 = n2 -> raise (Failure (exceptf n1))
    | _ :: t -> helper t
    | [] -> ()
  in helper (List.sort compare list)

let undeclared_identifier_error name =
    let msg = sprintf "undeclared identifier %s" name in
    raise (SemanticError msg)

let illegal_assignment_error = function
  | _ ->  let msg = sprintf "illegal assignment" in
    raise (SemanticError msg)

let illegal_unary_operation_error = function
  | _ ->  let msg = sprintf "illegal unary operator" in
    raise (SemanticError msg)

let illegal_binary_operation_error = function
  | _ ->  let msg = sprintf "illegal binary operator" in
    raise (SemanticError msg)

let check_assign lvaluet rvaluet = match lvaluet with
  | S.Bool when rvaluet = S.Int -> lvaluet
  | S.Enum(_) when  rvaluet = S.Int -> lvaluet
  | _ -> if lvaluet == rvaluet then lvaluet else illegal_assignment_error []

(* Checking Global Variables *)

let check_globals inp outp env = 
  let globals = inp @ outp in
  report_duplicate (fun n -> "duplicate global " ^ n) (List.map snd globals);
  List.fold_left (fun lst (typ,name) -> (name,typ)::lst) env.S.scope.variables globals

let check_fsm_decl fsms =
  report_duplicate (fun n -> "duplicate fsm " ^ n) (List.map (fun fd -> fd.S.fsm_name) fsms)

let check_enums types =
  report_duplicate (fun n -> "duplicate type " ^ n )
    (List.map (fun t -> t.S.type_name) types);
  List.map (fun lst -> report_duplicate (fun n -> "duplicate type " ^ n ) lst)
    (List.map (fun t -> t.S.type_values) types)

let add_local_vars vars env =
  report_duplicate (fun n -> "duplicate local " ^ n )
    (List.map (fun (_,s,_) -> s) vars);
  List.fold_left (fun lst (typ,name,_) -> (name,typ)::lst) env.S.scope.variables vars

let check_pubs pubs env =
  report_duplicate (fun n -> "duplicate public " ^ n )
    (List.map (fun (_,s,_) -> s) pubs);
  List.fold_left (fun lst (typ,name,_) -> (name,typ)::lst) env.S.scope.variables pubs

let type_of_identifier fsm scope name =
  let vdecl = try find_variable scope name
  with Not_found -> 
    try find_variable scope (fsm.S.fsm_name ^ "_" ^ name)
    with Not_found -> 
      undeclared_identifier_error name 
  in
  let (_,typ) = vdecl in
  typ

let rec get_expr fsm env = function (* A.expr *)
  | S.BoolLit(_) -> S.Bool
  | S.CharLit(_) -> S.Char
  | S.IntLit(_) -> S.Int
  | S.StringLit(_) -> S.String
  | S.Variable(name) -> 
    let var = try find_variable env.S.scope name
    with Not_found ->
      try find_variable env.S.scope (fsm.S.fsm_name ^ "_" ^ name)
      with Not_found ->
          raise (SemanticError("undeclared identifier " ^ name))
    in 
    let (_,vl) = var in
    vl
  | S.Uop(op, e) ->
      let t = get_expr fsm env e in
      (match op with
        | S.Neg when t = S.Int -> S.Int
        | S.Not when t = S.Bool -> S.Bool
        | _ -> illegal_unary_operation_error []
      )
  | S.Binop(e1,op,e2) -> 
      let t1 = get_expr fsm env e1
      and t2 = get_expr fsm env e2 in
      ( match op with 
        | S.Add | S.Sub | S.Mul | S.Div when t1 = S.Int && t2 = S.Int -> S.Int
        | S.Eq | S.Neq | S.Lt | S.Le | S.Gt | S.Ge when t1 = t2 -> S.Bool
        | S.Eq | S.Neq | S.Lt | S.Le | S.Gt | S.Ge when t1 = S.Int || t2 = S.Int -> S.Bool
        | S.And | S.Or when t1 = S.Bool && t2 = S.Bool -> S.Bool
        | _  -> illegal_binary_operation_error []
      )
  | S.Assign(name,exp) ->
      let lt = type_of_identifier fsm env.scope name
      and rt = get_expr fsm env exp in
      check_assign lt rt
  | S.Printf(_, lst) -> ignore(List.map (get_expr fsm env) lst); S.Int
  | S.Empty -> S.Int

let rec check_stmt env fsm = function (* stmts *)
  | S.Block(s_list) ->
    let sl =
      let env' =
        let scope' = { S.parent = Some(env.S.scope); S.variables = env.S.scope.variables } in
        { S.scope = scope' } in
      List.map (fun s -> check_stmt env' fsm s) s_list in
    ignore(sl);
  | S.State(_) -> ()
  | S.If(pred,sta,stb) -> 
      let e = get_expr fsm env pred in
      ignore((match e with
        | S.Int | S.Bool -> ()
        | _ -> raise (SemanticError("Illegal predicate type"))));
      ignore(check_stmt env fsm sta); ignore(check_stmt env fsm stb)
  | S.For(str,(na,nb,nc),stm) ->
    ignore(
      try List.find (fun (s, _) -> s = str) env.S.scope.variables
      with Not_found ->
        ignore(env.S.scope.variables <- (str,Int)::env.S.scope.variables); (str,S.Int));
      ignore(require_integer (get_expr fsm env (S.IntLit(na))) "Non-integer used in for loop");
      ignore(require_integer (get_expr fsm env (S.IntLit(nb))) "Non-integer used in for loop");
      ignore(require_integer (get_expr fsm env (S.IntLit(nc))) "Non-integer used in for loop");
      (check_stmt env fsm stm)
  | S.While(pred,stm) -> 
      let e = get_expr fsm env pred in
      ignore((match e with
        | S.Int | S.Bool -> ()
        | _ -> raise (SemanticError("Illegal predicate type"))));
      ignore(check_stmt env fsm stm)
  | S.Switch(exp, cases) -> 
      ignore(get_expr fsm env exp);
      ignore(check_cases env fsm cases)
  | S.Expr(e) -> ignore (get_expr fsm env e)
  | S.Goto(label) ->
    ignore(
      try List.find (fun (s,_) -> s=label) fsm.S.fsm_states
      with Not_found -> raise (SemanticError "No such state exists"))
  | S.Halt -> ()

and check_cases env fsm = function (* (expr * stmt) list *)
  | [] -> ()
  | (e,s_list)::tl -> ignore(get_expr fsm env e);
    ignore(
    let sl =
      let env' =
        let scope' = { S.parent = Some(env.S.scope); S.variables = env.S.scope.variables } in
        { S.scope = scope' } in
      List.map (fun s -> check_stmt env' fsm s) s_list in
    sl); ignore(check_cases env fsm tl)

let check_fsm_locals fsm env =
  (* Check FSM INSTANCE VARS: public and states *)
  report_duplicate (fun n -> "duplicate state " ^ n ^ " in " ^ fsm.S.fsm_name)
    (List.map fst fsm.S.fsm_states);
  report_duplicate (fun n -> "duplicate local " ^ n ^ " in " ^ fsm.S.fsm_name)
    (List.map (fun (_,s,_) -> s) fsm.S.fsm_locals);
  List.map (fun (typ,_,exp) -> check_assign (typ) (get_expr fsm env exp) ) fsm.S.fsm_locals

let check_body env fsm =
  check_stmt env fsm (S.Block(fsm.fsm_body))

let check_semant env fsm =
  let env' =
    let local_sym = { env.S.scope with variables = (add_local_vars fsm.S.fsm_locals env) @ env.S.scope.variables} in
    { S.scope = local_sym } in
  ignore(check_fsm_locals fsm env); ignore(check_body env' fsm)

let check program =
  let all_fsm_names = List.map (fun fsm_dec -> (fsm_dec.S.fsm_name,S.Int) ) program.S.fsms in
  let sym_tab = {S.parent = None; S.variables = all_fsm_names } in
  let env = {S.scope=sym_tab} in
  let new_syms = {sym_tab with variables = check_globals program.S.input program.S.output env} in
  let new_syms1 = {new_syms with variables = (check_pubs program.S.public env) @ (new_syms.S.variables)} in
  let env2 = { S.scope=new_syms1} in
  ignore(check_enums program.S.types);
  ignore(check_fsm_decl program.S.fsms);
  ignore(List.iter (check_semant env2) program.S.fsms)