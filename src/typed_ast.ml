open Ast
open Types

(* Printer Utility *)

module ExpressionPrinter = struct
  open Types
  open Printer
  open Printf

  let rec print_type_referenced_expr ~indent outc = function
    | ExprCall (receiver, meth, args) ->
      printf "send %a `%s" (print_expression ~indent:(indent+1)) receiver meth;
      (args |> List.iteri (fun _i expr -> print_expression ~indent:(indent+2) outc expr))
    | ExprFunc (name, args, body) ->
      printf "def `%s %a %a" name Ast.AstPrinter.print_args args (print_expression ~indent:(indent+1)) body
    | ExprLambda (args, body) ->
      printf "lambda %a %a" Ast.AstPrinter.print_args args (print_expression ~indent:(indent+1)) body
    | ExprVar ((name, _value))  ->
      printf "lvar `%s" name
    | ExprConst ((name, _value), base) ->
      printf "const %a `%s" (print_expression ~indent:(indent+1)) base name
    | ExprIVar ((name, _value)) ->
      printf "ivar `%s" name
    | ExprAssign (name, expr) ->
      printf "lvasgn `%s %a" name (print_expression ~indent:(indent+1)) expr
    | ExprIVarAssign (name, expr) ->
      printf "ivasgn %s %a" name (print_expression ~indent:(indent+1)) expr
    | ExprConstAssign (name, expr) ->
      printf "casgn %s %a" name (print_expression ~indent:(indent+1)) expr
    | ExprValue (value) ->
      printf "%a" Ast.AstPrinter.print_value value
    | ExprBlock (expr1, expr2) ->
      printf "%a %a" (print_expression ~indent:(indent+1)) expr1 (print_expression ~indent:(indent+1)) expr2

  and print_expression ~indent _outc (expr, metadata) =
    if (indent <> 1) then printf "\n";
    let { type_reference; _ } = metadata in
    (* printf "# %a\n" Location.print_loc expr_loc; *)
    printf "%*s(%a : %s)" indent " "
      (print_type_referenced_expr ~indent:indent)
      expr
      (print_type_reference type_reference);
    if (indent = 1) then printf "\n"

  let print_constraint _k v =
    let format_constraint s = Printf.sprintf "\027[31m%s\027[m" s in
    let prefix = format_constraint "CONSTRAINT:" in
    let open Constraint_engine in
    match v with
    | Constraints.Method (method_name, args, receiver_t, return_t) ->
      printf "%s %-20s %s.%s(%s) == %s\n"
        prefix
        "Method"
        (print_type_reference receiver_t)
        method_name
        (if List.length args > 0 then
           (String.concat ", " (List.map (fun arg -> print_type_reference arg) args))
         else "")
        (print_type_reference return_t)
    | Constraints.Literal (a, t) ->
      printf "%s %-20s %s = %s\n" prefix "Literal" (print_type_reference a) (type_to_str t)
    | Constraints.SubType (child, parent) ->
      printf "%s %-20s %s < %s\n" prefix "SubType" (print_type_reference child) (print_type_reference parent)

  let print_constraint_map constraint_map =
    constraint_map |> Constraint_engine.Constraints.Map.iter (fun k vs ->
        vs |> List.iter (fun v -> print_constraint k v);
      )
end

(* Annotations *)

let binding_for_expr = function
  | ExprAssign (name, _)
  | ExprIVarAssign (name, _)
  | ExprConstAssign (name, _)
  | ExprFunc (name, _, _) -> Some(name)
  | _ -> None

let annotate expression =
  let annotate_expression expr location_meta =
    let t = Types.gen_fresh_t () in
    let t_node = t |> Disjoint_set.make
      ~root:false
      ~metadata:{
        location = (Some location_meta);
        binding = binding_for_expr expr;
        level = Unresolved
      } in
    (expr, { expr_loc = location_meta; type_reference = t_node; level = 0; })
  in let (expr, location_meta) = expression in
  replace_metadata annotate_expression expr location_meta

(* AST -> TypedAST *)
let resolve_types ast =
  let annotate_expression expr ({ type_reference; _ } as meta) =
    (expr, { meta with type_reference = Disjoint_set.find type_reference })
  in let (expr, meta) = ast in
  replace_metadata annotate_expression expr meta
