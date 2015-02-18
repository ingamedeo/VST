Require Import floyd.proofauto.
Require Import mirror_cancel.
Require Import reverse_defs.

Local Open Scope logic.


Lemma unfold_entail :
name _p ->
name _v ->
name _w ->
name _t ->
forall (sh : share) (contents : list val),
  writable_share sh ->
  forall (cts1 cts2 : list val) (w v : val),
    isptr v ->
   exists (a : Share.t) (b : val),
     PROP  (contents = rev cts1 ++ cts2)
     LOCAL  (tc_environ Delta2; `(eq w) (eval_id _w); 
     `(eq v) (eval_id _v))
     SEP  (`(lseg LS sh cts1 w nullval); `(lseg LS sh cts2 v nullval))
     |-- local (tc_expr Delta2 (Etempvar _v (tptr t_struct_list))) &&
         (`(field_at a t_struct_list _tail b)
            (eval_expr (Etempvar _v (tptr t_struct_list))) * TT).
Proof.
intros.
eexists; eexists.
go_lower0.
Time rcancel.
Abort. (*we need a lemma!*)

Lemma while_entail2 :
  name _t ->
  name _p ->
  name _s ->
  name _h ->
  forall (sh : share) (contents : list int),
  PROP  ()
  LOCAL  (tc_environ Delta;
         `eq (eval_id _t) (eval_expr (Etempvar _p (tptr t_struct_list)));
         `eq (eval_id _s) (eval_expr (Econst_int (Int.repr 0) tint)))
  SEP  (`(lseg LS sh (map Vint contents)) (eval_id _p) `nullval)
          |-- EX  cts : list int,
  PROP  ()
  LOCAL 
        (`(eq (Vint (Int.sub (sum_int contents) (sum_int cts)))) (eval_id _s))
  SEP  (TT; `(lseg LS sh (map Vint cts)) (eval_id _t) `nullval).
Proof.
intros.
go_lower0.
Time rcancel.
rewrite Int.sub_idem. auto. 
Qed.

Lemma while_entail1 :
  name _t ->
  name _p ->
  name _s ->
  name _h ->
  forall (sh : share) (contents : list int),
   PROP  ()
   LOCAL 
   (tc_environ
      Delta;
   `eq (eval_id _t) (eval_expr (Etempvar _p (tptr t_struct_list))
);
   `eq (eval_id _s) (eval_expr (Econst_int (Int.repr 0) tint)))
   SEP  (`(lseg LS sh (map Vint contents)) (eval_id _p) `nullval)
   |-- PROP  ()
       LOCAL 
       (`(eq (Vint (Int.sub (sum_int contents) (sum_int contents))))
          (eval_id _s))
       SEP  (TT; `(lseg LS sh (map Vint contents)) (eval_id _t) `nullval).
Proof.
intros.
go_lower0.
rewrite Int.sub_idem. unfold Int.zero.
Time rcancel.
Qed.

Lemma load_entail1 : 
 forall (i : int) (cts : list int) (t0 y : val) (sh : share)
     (contents : list int) (t : name _t) (p_ : name _p) 
     (s : name _s) (h : name _h),
   exists a, exists b,
   PROP  ()
   LOCAL  (tc_environ Delta; `(eq t0) (eval_id _t);
   `(eq (Vint (Int.sub (sum_int contents) (sum_int (i :: cts)))))
     (eval_id _s))
   SEP 
   (`(field_at sh t_struct_list _head (Vint i))
      (fun _ : lift_S (LiftEnviron mpred) => t0);
   `(field_at sh t_struct_list _tail y)
     (fun _ : lift_S (LiftEnviron mpred) => t0);
   `(lseg LS sh (map Vint cts)) `y `nullval; TT)
   |-- local (tc_expr Delta (Etempvar _t (tptr t_struct_list))) &&
       (`(field_at a t_struct_list _head b)
          (eval_expr (Etempvar _t (tptr t_struct_list))) * TT).
Proof.
intros. 
eexists. eexists.
go_lower0.
Time rcancel.
Qed.

Goal forall contents sh rho,
(eval_id _t rho) = (eval_id _p rho) ->
lseg LS sh (map Vint contents) (eval_id _t rho) nullval * emp |--
lseg LS sh (map Vint contents) (eval_id _p rho) nullval * emp.
intros.
rcancel.
Qed.


(* trying to test if my reified hints are usable by Mirror *)
Goal forall T sh id y, field_at sh T id y nullval |-- !!False && emp.
Proof.
intros.
rcancel. 
Qed.

Goal forall (a b c d: nat), a = b -> b = c -> c = d ->
                            functions.P a |-- functions.P d.
Proof.
intros.
rcancel.
Qed.

(* need to deal with singleton? *)
(* we may need also to add hnf somewhere in mirror_cancel_default. *)
(* mirror_cancel_default. *)

Goal forall (A B : Prop),(!!(A /\ B) && emp |-- !!( B) && emp).
Proof.
intros.
rcancel.
Qed.


Goal forall n, functions.P n |-- functions.Q n.
intros.
rcancel.
Qed.


Parameter X : Z -> mpred.


Goal X (1 + 3) |-- X (2 + 2).
intros.
rcancel.
Qed.

Goal  emp |-- emp.
Proof.
rcancel.
Qed.

Goal forall a,  a |-- a.
Proof.
intros.
rcancel.
Qed.

Goal forall a b, a * b |-- b * a.
intros.
rcancel.
Qed.

Goal forall a ,
 !!True && a
   |-- !!True &&
       (a * !!True).
Proof.
intros.
rcancel.
Qed.

Goal
 forall (i : int) (cts : list int) (t0 y : val) (sh : share)
     (contents : list int) (t : name _t) (p_ : name _p) 
     (s : name _s) (h : name _h) (a b c d : mpred) (e: Prop),
     (!!True * emp) * a
   |-- a * !!True.
Proof.
intros.
rcancel.
Qed.

