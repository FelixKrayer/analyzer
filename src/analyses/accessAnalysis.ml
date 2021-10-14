(** Acces and data race analysis. *)

module M = Messages
module LF = LibraryFunctions
open Prelude.Ana
open Analyses
open GobConfig


(** Access and rata race analyzer without base --- this is the new standard *)
module Spec =
struct
  include Analyses.DefaultSpec

  let name () = "access"

  (** Add current lockset alongside to the base analysis domain. Global data is collected using dirty side-effecting. *)
  module D = Lattice.Unit
  module C = Lattice.Unit

  module G =
  struct
    module A =
    struct
      include Printable.Std
      type t = int * bool * CilType.Location.t * CilType.Exp.t * Access.LSSet.t [@@deriving eq, ord]

      let hash (conf, w, loc, e, lp) = 0 (* TODO: never hashed? *)

      let pretty () (conf, w, loc, e, lp) =
        Pretty.dprintf "%d, %B, %a, %a, %a" conf w CilType.Location.pretty loc CilType.Exp.pretty e Access.LSSet.pretty lp

      let show x = Pretty.sprint ~width:max_int (pretty () x)
      let printXml f x = BatPrintf.fprintf f "<value>\n<data>\n%s\n</data>\n</value>\n" (XmlUtil.escape (show x))
      let to_yojson x = `String (show x)
    end
    module AS = SetDomain.Make (A)
    module LS = SetDomain.Reverse (SetDomain.ToppedSet (Access.LabeledString) (struct let topname = "top" end))
    module PM = MapDomain.MapBot (Printable.Option (Access.LSSet) (struct let name = "None" end)) (Lattice.Prod (AS) (LS))
    module T =
    struct
      include Printable.Std
      include Access.Acc_typHashable

      let compare = [%ord: Access.acc_typ]

      let pretty = Access.d_acct

      let show x = Pretty.sprint ~width:max_int (pretty () x)
      let printXml f x = BatPrintf.fprintf f "<value>\n<data>\n%s\n</data>\n</value>\n" (XmlUtil.escape (show x))
      let to_yojson x = `String (show x)
    end
    module TM = MapDomain.MapBot (T) (PM)
    module O =
    struct
      include Printable.Std
      type t = Access.offs [@@deriving eq, ord]

      let hash _ = 0 (* TODO: not used? *)

      let pretty = Access.d_offs

      let show x = Pretty.sprint ~width:max_int (pretty () x)
      let printXml f x = BatPrintf.fprintf f "<value>\n<data>\n%s\n</data>\n</value>\n" (XmlUtil.escape (show x))
      let to_yojson x = `String (show x)
    end
    module OM = MapDomain.MapBot (O) (TM)
    include OM

    let leq _ _ = true (* HACK: to pass verify*)
  end

  let none_varinfo = ref dummyFunDec.svar

  let init marshal =
    none_varinfo := GU.create_var @@ makeGlobalVar "__NONE__" voidType

  let side_access ctx ty lv_opt ls_opt (conf, w, loc, e, lp) =
    let (g, o) = lv_opt |? (!none_varinfo, `NoOffset) in
    let d =
      let open G in
      OM.singleton o (
        TM.singleton ty (
          PM.singleton ls_opt (
            (AS.singleton (conf, w, loc, e, lp), `Lifted lp)
          )
        )
      )
    in
    ctx.sideg g d

  let do_access (ctx: (D.t, G.t, C.t) ctx) (w:bool) (reach:bool) (conf:int) (e:exp) =
    let open Queries in
    let part_access ctx (e:exp) (vo:varinfo option) (w: bool) =
      ctx.emit (Access {var_opt=vo; write=w});
      (*partitions & locks*)
      ctx.ask (PartAccess {exp=e; var_opt=vo; write=w})
    in
    let add_access conf vo oo =
      let (po,pd) = part_access ctx e vo w in
      Access.add (side_access ctx) e w conf vo oo (po,pd);
    in
    let add_access_struct conf ci =
      let (po,pd) = part_access ctx e None w in
      Access.add_struct (side_access ctx) e w conf (`Struct (ci,`NoOffset)) None (po,pd)
    in
    let has_escaped g = ctx.ask (Queries.MayEscape g) in
    (* The following function adds accesses to the lval-set ls
       -- this is the common case if we have a sound points-to set. *)
    let on_lvals ls includes_uk =
      let ls = LS.filter (fun (g,_) -> g.vglob || has_escaped g) ls in
      let conf = if reach then conf - 20 else conf in
      let conf = if includes_uk then conf - 10 else conf in
      let f (var, offs) =
        let coffs = Lval.CilLval.to_ciloffs offs in
        if CilType.Varinfo.equal var dummyFunDec.svar then
          add_access conf None (Some coffs)
        else
          add_access conf (Some var) (Some coffs)
      in
      LS.iter f ls
    in
    let reach_or_mpt = if reach then ReachableFrom e else MayPointTo e in
    match ctx.ask reach_or_mpt with
    | ls when not (LS.is_top ls) && not (Queries.LS.mem (dummyFunDec.svar,`NoOffset) ls) ->
      (* the case where the points-to set is non top and does not contain unknown values *)
      on_lvals ls false
    | ls when not (LS.is_top ls) ->
      (* the case where the points-to set is non top and contains unknown values *)
      let includes_uk = ref false in
      (* now we need to access all fields that might be pointed to: is this correct? *)
      begin match ctx.ask (ReachableUkTypes e) with
        | ts when Queries.TS.is_top ts ->
          includes_uk := true
        | ts ->
          if Queries.TS.is_empty ts = false then
            includes_uk := true;
          let f = function
            | TComp (ci, _) ->
              add_access_struct (conf - 50) ci
            | _ -> ()
          in
          Queries.TS.iter f ts
      end;
      on_lvals ls !includes_uk
    | _ ->
      add_access (conf - 60) None None

  let access_one_top ?(force=false) ctx write reach exp =
    (* ignore (Pretty.printf "access_one_top %b %b %a:\n" write reach d_exp exp); *)
    if force || ThreadFlag.is_multi (Analyses.ask_of_ctx ctx) then (
      let conf = 110 in
      if reach || write then do_access ctx write reach conf exp;
      Access.distribute_access_exp (do_access ctx) false false conf exp;
    )

  (** We just lift start state, global and dependency functions: *)
  let startstate v = ()
  let threadenter ctx lval f args = [()]
  let exitstate  v = ()


  (** Transfer functions: *)

  let assign ctx lval rval : D.t =
    (* ignore global inits *)
    if !GU.global_initialization then ctx.local else begin
      access_one_top ctx true  false (AddrOf lval);
      access_one_top ctx false false rval;
      ctx.local
    end

  let branch ctx exp tv : D.t =
    access_one_top ctx false false exp;
    ctx.local

  let return ctx exp fundec : D.t =
    begin match exp with
      | Some exp -> access_one_top ctx false false exp
      | None -> ()
    end;
    ctx.local

  let body ctx f : D.t =
    begin match f.svar.vname with
    | "__goblint_dummy_init" ->
      ctx.sideg !none_varinfo (G.bot ()) (* make one side effect to None, otherwise verify will always fail due to Lift2 bottom *)
    | _ ->
      ()
    end;
    ctx.local

  let special ctx lv f arglist : D.t =
    match (LF.classify f.vname arglist, f.vname) with
    (* TODO: remove cases *)
    | _, "_lock_kernel" ->
      ctx.local
    | _, "_unlock_kernel" ->
      ctx.local
    | `Lock (failing, rw, nonzero_return_when_aquired), _
      -> ctx.local
    | `Unlock, "__raw_read_unlock"
    | `Unlock, "__raw_write_unlock"  ->
      ctx.local
    | `Unlock, _ ->
      ctx.local
    | _, "spinlock_check" -> ctx.local
    | _, "acquire_console_sem" when get_bool "kernel" ->
      ctx.local
    | _, "release_console_sem" when get_bool "kernel" ->
      ctx.local
    | _, "__builtin_prefetch" | _, "misc_deregister" ->
      ctx.local
    | _, "__VERIFIER_atomic_begin" when get_bool "ana.sv-comp.functions" ->
      ctx.local
    | _, "__VERIFIER_atomic_end" when get_bool "ana.sv-comp.functions" ->
      ctx.local
    | _, "pthread_cond_wait"
    | _, "pthread_cond_timedwait" ->
      ctx.local
    | _, x ->
      let arg_acc act =
        match LF.get_threadsafe_inv_ac x with
        | Some fnc -> (fnc act arglist)
        | _ -> arglist
      in
      List.iter (access_one_top ctx false true) (arg_acc `Read);
      List.iter (access_one_top ctx true  true ) (arg_acc `Write);
      (match lv with
      | Some x -> access_one_top ctx true false (AddrOf x)
      | None -> ());
      ctx.local

  let enter ctx lv f args : (D.t * D.t) list =
    [(ctx.local,ctx.local)]

  let combine ctx lv fexp f args fc al =
    access_one_top ctx false false fexp;
    begin match lv with
      | None      -> ()
      | Some lval -> access_one_top ctx true false (AddrOf lval)
    end;
    List.iter (access_one_top ctx false false) args;
    al


  let threadspawn ctx lval f args fctx =
    (* must explicitly access thread ID lval because special to pthread_create doesn't if singlethreaded before *)
    begin match lval with
    | None -> ()
    | Some lval -> access_one_top ~force:true ctx true false (AddrOf lval) (* must force because otherwise doesn't if singlethreaded before *)
    end;
    ctx.local

  let query ctx (type a) (q: a Queries.t): a Queries.result =
    match q with
    | WarnGlobal g ->
      ignore (Pretty.printf "WarnGlobal %a\n" CilType.Varinfo.pretty g);
      let open Access in
      let allglobs = get_bool "allglobs" in
      let debug = get_bool "dbg.debug" in
      let open G in
      let om = ctx.global g in
      OM.iter (fun o tm ->
          let lv =
            if CilType.Varinfo.equal g !none_varinfo then (
              assert (o = `NoOffset);
              None
            )
            else
              Some (g, o)
          in
          TM.iter (fun ty pm ->
              let check_safe ls (accs, lp) prev_safe =
                (* TODO: Access uses polymorphic Set? *)
                let accs = Set.of_list (AS.elements accs) in (* TODO: avoid converting between sets *)
                Access.check_safe ls (accs, lp) prev_safe
              in
              let g (ls, (acs,_)) =
                let h (conf,w,loc,e,lp) =
                  let d_ls () = match ls with
                    | None -> Pretty.text " is ok" (* None is used by add_one when access partitions set is empty (not singleton), so access is considered unracing (single-threaded or bullet region)*)
                    | Some ls when LSSet.is_empty ls -> nil
                    | Some ls -> text " in " ++ LSSet.pretty () ls
                  in
                  let atyp = if w then "write" else "read" in
                  let d_msg () = dprintf "%s%t with %a (conf. %d)" atyp d_ls LSSet.pretty lp conf in
                  let doc =
                    if debug then
                      dprintf "%t  (exp: %a)" d_msg d_exp e
                    else
                      d_msg ()
                  in
                  (doc, Some loc)
                in
                AS.elements acs
                |> List.enum
                |> Enum.map h
              in
              let msgs () =
                PM.bindings pm
                |> List.enum
                |> Enum.concat_map g
                |> List.of_enum
              in
              match PM.fold check_safe pm None with
              | None ->
                if allglobs then
                  M.msg_group Success ~category:Race "Memory location %a (safe)" d_memo (ty,lv) (msgs ())
              | Some n ->
                M.msg_group Warning ~category:Race "Memory location %a (race with conf. %d)" d_memo (ty,lv) n (msgs ())
            ) tm
        ) om
    | _ -> Queries.Result.top q
end

let _ =
  MCP.register_analysis (module Spec : MCPSpec)
