Require Import floyd.base.
Require Import floyd.client_lemmas.
Import ListNotations.

Fixpoint deadvars_remove1 i vl :=
 match vl with
 | j::vl' => if Pos.eqb i j 
             then deadvars_remove1 i vl' 
             else j :: deadvars_remove1 i vl' 
 | nil => nil
 end.

Fixpoint deadvars_remove (e: expr) (vl: list ident) : list ident :=
 match e with
 | Etempvar i _ => deadvars_remove1 i vl
 | Ederef e1 _ => deadvars_remove e1 vl
 | Eaddrof e1 _ => deadvars_remove e1 vl
 | Eunop _ e1 _ => deadvars_remove e1 vl
 | Ebinop _ e1 e2 _ => deadvars_remove e2 (deadvars_remove e1 vl)
 | Ecast e1 _ => deadvars_remove e1 vl
 | Efield e1 _ _ => deadvars_remove e1 vl
 | _ => vl
 end.

Fixpoint deadvars_removel (el: list expr) (vl: list ident) : list ident :=
  match el with
  | nil => vl 
  | e::el' => let vl' := deadvars_remove e vl in deadvars_removel el' vl'
  end.

Fixpoint deadvars_dead (i: ident) (vl: list ident) : list ident * list ident :=
 match vl with
 | j::vl' => if Pos.eqb i j 
             then ([i],vl')
             else let (k,vl'') := deadvars_dead i vl' in (k,j::vl')
 | nil => (nil, nil)
 end.

Fixpoint deadvars_stmt (vl: list ident) (dead: list ident) (c: statement) 
                   (cont: list ident -> list ident -> list ident) : list ident :=
  match vl with nil => dead | _ =>
   match c with
   | Sskip => cont vl dead
   | Sassign e1 e2 => let vl' := deadvars_removel [e1;e2] vl in
                         cont vl' dead
   | Sset i e => let vl' := deadvars_remove e vl in
                     let (d,vl'') := deadvars_dead i vl' in
                      cont vl'' (d++dead)
   | Scall i e el => let vl' := deadvars_removel (e::el) vl in
                      let (d,vl'') := match i with
                                      | Some i' => deadvars_dead i' vl'
                                      | None => (nil,vl')
                                      end
                      in cont vl'' (d++dead)
   | Sbuiltin i ef tl el =>
                     let vl' := deadvars_removel el vl in
                      let (d,vl'') := match i with
                                      | Some i' => deadvars_dead i' vl'
                                      | None => (nil,vl')
                                      end
                      in cont vl'' (d++dead)
   | Ssequence c1 c2 =>
          deadvars_stmt vl dead c1 (fun vl' dead' => 
             deadvars_stmt vl' dead' c2 cont)
   | Sreturn None => vl++dead
   | Sreturn (Some e) => let vl' := deadvars_removel [e] vl
                          in vl' ++ dead
   | _ => dead
   end
  end.

Fixpoint temps_of_localdefs (dl: list localdef) : list ident :=
 match dl with
 | nil => nil
 | temp i _ :: dl' => i :: temps_of_localdefs dl'
 | _ :: dl' => temps_of_localdefs dl'
 end.

Fixpoint deadvars_post (post: list ident) (vl: list ident) (dead: list ident) : list ident :=
 match post with
 | nil => vl++dead
 | i :: post' => deadvars_post post' (deadvars_remove1 i vl) dead
 end.

Ltac inhabited_value T :=
 match T with
 | nat => constr:(O)
 | Z => constr:(0%Z)
 | list ?A => constr:(@nil A)
 | positive => xH
 | bool => false
 | _ => match goal with x:T |- _ => x | x := _ : T |- _ => x end
 end.

Fixpoint expr_temps (e: expr) (vl: list ident) : list ident :=
 match e with
 | Etempvar i _ => if id_in_list i vl then vl else i::vl
 | Ederef e1 _ => expr_temps e1 vl
 | Eaddrof e1 _ => expr_temps e1 vl
 | Eunop _ e1 _ => expr_temps e1 vl
 | Ebinop _ e1 e2 _ => expr_temps e2 (expr_temps e1 vl)
 | Ecast e1 _ => expr_temps e1 vl
 | Efield e1 _ _ => expr_temps e1 vl
 | _ => vl
 end.

Ltac locals_of_assert P :=
 match P with
 | (PROPx _ (LOCALx ?Q _)) => constr:(temps_of_localdefs Q)
 | emp => constr:(@nil ident)
 | andp ?A ?B => let a := locals_of_assert A in
                  let b := locals_of_assert B in
                    constr:(a++b)
 | local (`(eq _) (eval_expr ?E)) =>
            let vl := constr:(expr_temps E nil) in vl
 | @exp _ _ ?T ?F =>
    let x := inhabited_value T in
     let d := constr:(F x) in
      let d := eval cbv beta in d in 
       let d := locals_of_assert d in
           d
 end.


Ltac locals_of_ret_assert Post :=
 match Post with
 | @abbreviate ret_assert ?P => locals_of_ret_assert P
 | normal_ret_assert ?P => locals_of_assert P
 | loop1_ret_assert ?P _ => locals_of_assert P
 | loop2_ret_assert ?P _ => locals_of_assert P
 | function_body_ret_assert _ _ => constr:(@nil ident)
 | frame_ret_assert ?A ?B =>
     let vlA :=  locals_of_ret_assert A
      in let vlB := locals_of_assert B
       in let vl := constr:(vlA++vlB)
        in vl     
 end.

Ltac deadvars := 
 match goal with
 | X := @abbreviate ret_assert ?Q |-
    semax _ ?P ?c ?Y =>
    constr_eq X Y; 
     let vl := locals_of_assert P in 
     let post := locals_of_ret_assert Q in
     let d := constr:(deadvars_stmt vl nil c (deadvars_post post)) in
      let d := eval compute in d in
       match d with nil => idtac | _ => 
           idtac "Dropping dead vars!"; drop_LOCALs d
       end
 | |- _ |-- _ => idtac
 end.