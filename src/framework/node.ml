open GoblintCil
open Pretty

include Printable.Std

include Node0

let name () = "node"

(* TODO: remove this? *)
(** Pretty node plainly with entire stmt. *)
let pretty_plain () = function
  | Statement s -> text "Statement " ++ dn_stmt () s
  | LongjmpTo s -> text "LongjmpTo Statement" ++ dn_stmt () s
  | Function f -> text "Function " ++ text f.svar.vname
  | LongjmpFromFunction f ->  text "Longjmp from Function " ++ text f.svar.vname
  | FunctionEntry f -> text "FunctionEntry " ++ text f.svar.vname

(* TODO: remove this? *)
(** Pretty node plainly with stmt location. *)
let pretty_plain_short () = function
  | Statement s -> text "Statement @ " ++ CilType.Location.pretty () (Cilfacade.get_stmtLoc s)
  | LongjmpTo s -> text "LongjmpTo Statement @ " ++ CilType.Location.pretty () (Cilfacade.get_stmtLoc s)
  | Function f -> text "Function " ++ text f.svar.vname
  | LongjmpFromFunction f ->  text "Longjmp from Function " ++ text f.svar.vname
  | FunctionEntry f -> text "FunctionEntry " ++ text f.svar.vname

(** Pretty node for solver variable tracing with short stmt. *)
let pretty_trace () = function
  | Statement stmt   -> dprintf "node %d \"%a\"" stmt.sid Cilfacade.stmt_pretty_short stmt
  | LongjmpTo stmt   -> dprintf "LongjmpTo node %d \"%a\"" stmt.sid Cilfacade.stmt_pretty_short stmt
  | Function      fd -> dprintf "call of %s (%d)" fd.svar.vname fd.svar.vid
  | LongjmpFromFunction fd ->  dprintf "Longjmp from call of %s (%d)" fd.svar.vname fd.svar.vid
  | FunctionEntry fd -> dprintf "entry state of %s (%d)" fd.svar.vname fd.svar.vid

(** Output functions for Printable interface *)
let pretty () x = pretty_trace () x
include Printable.SimplePretty (
  struct
    type nonrec t = t
    let pretty = pretty
  end
  )
(* TODO: deriving to_yojson gets overridden by SimplePretty *)

(** Show node ID for CFG and results output. *)
let show_id = function
  | Statement stmt   -> string_of_int stmt.sid
  | LongjmpTo stmt   -> "longjmpto" ^ string_of_int stmt.sid
  | Function fd      -> "ret" ^ string_of_int fd.svar.vid
  | LongjmpFromFunction fd      -> "longjmpfrom" ^ string_of_int fd.svar.vid
  | FunctionEntry fd -> "fun" ^ string_of_int fd.svar.vid

(** Show node label for CFG. *)
let show_cfg = function
  | Statement stmt   -> string_of_int stmt.sid (* doesn't use this but defaults to no label and uses ID from show_id instead *)
  | LongjmpTo stmt   -> "longjmpto" ^ string_of_int stmt.sid
  | Function fd      -> "return of " ^ fd.svar.vname ^ "()"
  | LongjmpFromFunction fd      -> "longjmp from " ^ fd.svar.vname ^ "()"
  | FunctionEntry fd -> fd.svar.vname ^ "()"


(** Find [fundec] which the node is in. In an incremental run this might yield old fundecs for pseudo-return nodes from the old file. *)
let find_fundec (node: t) =
  match node with
  | Statement stmt
  | LongjmpTo stmt  -> Cilfacade.find_stmt_fundec stmt
  | Function fd
  | LongjmpFromFunction fd
  | FunctionEntry fd -> fd

(** @raise Not_found *)
let of_id s =
  let ix = Str.search_forward (Str.regexp {|[0-9]+$|}) s 0 in
  let id = int_of_string (Str.string_after s ix) in
  let prefix = Str.string_before s ix in
  match ix with
  | 0 -> Statement (Cilfacade.find_stmt_sid id)
  | _ ->
    let fundec = Cilfacade.find_varinfo_fundec {dummyFunDec.svar with vid = id} in
    match prefix with
    | "ret" -> Function fundec
    | "fun" -> FunctionEntry fundec
    | _     -> raise Not_found
(* TODO: longjmpTo, LongjmpFromFunction? *)
