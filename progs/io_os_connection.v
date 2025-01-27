Require Import List.
Require Import ZArith.
Require Import Psatz.
Require Import ITree.ITree.
Require Import ITree.Interp.Traces.
Require Import compcert.lib.Maps.
Require Import compcert.lib.Integers.
Require Import compcert.common.Memory.
Require Import compcert.common.Values.
Require Import VST.progs.io_specs.
Require Import VST.progs.io_mem_specs.
Require Import VST.progs.io_dry.
Require Import VST.progs.io_mem_dry.
Require Import VST.progs.io_os_specs.
Require Import VST.floyd.sublist.
Require Import VST.progs.os_combine.
Import ExtLib.Structures.Monad.

Local Ltac inj :=
  repeat match goal with
  | H: _ = _ |- _ => assert_succeeds (injection H); inv H
  end.

Local Ltac prename' pat H name :=
  match type of H with
  | context[?pat'] => unify pat pat'; rename H into name
  end.

Tactic Notation "prename" open_constr(pat) "into" ident(name) :=
  lazymatch goal with
  | H: pat, H': pat |- _ =>
      fail 0 "Multiple possible matches for" pat ":" H "and" H'
  | H: pat |- _ => prename' pat H name
  | H: context[pat], H': context[pat] |- _ =>
      fail 0 "Multiple possible matches for" pat ":" H "and" H'
  | H: context[pat] |- _ => prename' pat H name
  | _ => fail 0 "No hypothesis matching" pat
  end.

Local Ltac simpl_rev :=
  repeat (rewrite rev_app_distr; cbn [rev app]);
  rewrite <- ?app_assoc; cbn [rev app];
  rewrite ?rev_involutive.

Local Ltac simpl_rev_in H :=
  repeat (rewrite rev_app_distr in H; cbn [rev app] in H);
  rewrite <- ?app_assoc in H; cbn [rev app] in H;
  rewrite ?rev_involutive in H.

Local Ltac destruct_spec Hspec :=
  repeat match type of Hspec with
  | match ?x with _ => _ end = _ => destruct x eqn:?; subst; inj; try discriminate
  end.

(** Helper Lemmas *)
Section ListFacts.

  Context {A : Type}.
  Variable Aeq : forall (x y : A), {x = y} + {x <> y}.

  (** common_prefix *)
  Fixpoint common_prefix (xs ys : list A) : list A :=
    match xs, ys with
    | x :: xs', y :: ys' =>
      if Aeq x y then x :: common_prefix xs' ys' else nil
    | _, _ => nil
    end.

  Definition strip_common_prefix (xs ys : list A) : list A :=
    let longer := if length xs <=? length ys then ys else xs in
    skipn (length (common_prefix xs ys)) longer.

  Lemma common_prefix_sym : forall xs ys,
    common_prefix xs ys = common_prefix ys xs.
  Proof.
    induction xs as [| x xs]; destruct ys as [| y ys]; cbn; auto.
    destruct (Aeq x y), (Aeq y x); congruence.
  Qed.

  Lemma common_prefix_correct : forall xs ys pre,
    pre = common_prefix xs ys ->
    exists rest, ys = pre ++ rest.
  Proof.
    induction xs as [| x xs]; destruct ys as [| y ys]; intros; subst; cbn; eauto.
    destruct (Aeq x y); cbn; subst; eauto.
    edestruct (IHxs ys) as (? & Heq); eauto.
    esplit; rewrite <- Heq; eauto.
  Qed.

  Lemma common_prefix_firstn : forall xs ys,
    let pre := common_prefix xs ys in
    pre = firstn (length pre) xs.
  Proof.
    induction xs as [| x xs]; destruct ys as [| y ys]; cbn; auto.
    destruct (Aeq x y); cbn; congruence.
  Qed.

  Lemma common_prefix_length : forall xs ys,
    length (common_prefix xs ys) <= length xs.
  Proof.
    induction xs as [| x xs]; destruct ys as [| y ys]; cbn; try lia.
    destruct (Aeq x y); cbn; try lia.
    specialize (IHxs ys); lia.
  Qed.

  Lemma common_prefix_full : forall xs,
    common_prefix xs xs = xs.
  Proof.
    induction xs as [| x xs]; cbn; auto.
    destruct (Aeq x x); cbn; congruence.
  Qed.

  Lemma common_prefix_app : forall xs ys,
    common_prefix xs (xs ++ ys) = xs.
  Proof.
    induction xs as [| x xs]; cbn; auto.
    destruct (Aeq x x); cbn; congruence.
  Qed.

  Lemma strip_common_prefix_correct : forall xs ys,
    length xs <= length ys ->
    let post := strip_common_prefix xs ys in
    ys = common_prefix xs ys ++ post.
  Proof.
    induction xs as [| x xs]; destruct ys as [| y ys]; cbn; intros; auto; try lia.
    rewrite leb_correct by lia.
    destruct (Aeq _ _); subst; cbn; auto.
    rewrite common_prefix_sym.
    rewrite common_prefix_firstn at 1.
    rewrite firstn_skipn; auto.
  Qed.

  (** Misc tl/hd_error facts *)
  Lemma in_tail : forall (xs : list A) x,
    In x (tl xs) -> In x xs.
  Proof. destruct xs; intros *; cbn; auto. Qed.

  Lemma tail_not_nil_has_head : forall (xs ys : list A),
    ys <> nil ->
    tl xs = ys ->
    exists x, xs = x :: ys.
  Proof. destruct xs; cbn; intros; subst; eauto; easy. Qed.

  Lemma Zlength_tail : forall (xs : list A),
    (Zlength (tl xs) <= Zlength xs)%Z.
  Proof.
    destruct xs; [cbn; lia |].
    rewrite Zlength_cons; cbn; lia.
  Qed.

  Lemma Zlength_tail_strong : forall (xs : list A),
    xs <> nil ->
    (Zlength (tl xs) = Zlength xs - 1)%Z.
  Proof.
    destruct xs; [easy |].
    intros; cbn [tl].
    rewrite Zlength_cons; lia.
  Qed.

  Lemma skipn_tl : forall n (xs : list A),
    skipn (S n) xs = tl (skipn n xs).
  Proof. induction n; destruct xs; cbn in *; auto. Qed.

  Lemma tl_app : forall (xs ys : list A),
    xs <> nil ->
    tl (xs ++ ys) = tl xs ++ ys.
  Proof. induction xs; cbn; easy. Qed.

  Lemma hd_error_app : forall (xs ys : list A) x,
    hd_error xs = Some x ->
    hd_error (xs ++ ys) = Some x.
  Proof. destruct xs; cbn; easy. Qed.

  Lemma hd_error_app_case : forall (xs : list A) x,
    hd_error (xs ++ x :: nil) = hd_error xs \/ xs = nil.
  Proof. destruct xs; auto. Qed.

  Lemma hd_error_tl : forall (xs : list A) x,
    hd_error (tl xs) = Some x ->
    exists y, hd_error xs = Some y.
  Proof. destruct xs; cbn; eauto. Qed.

  Lemma hd_error_in : forall (xs : list A) x,
    hd_error xs = Some x ->
    In x xs.
  Proof. destruct xs; cbn; intros; inj; auto; easy. Qed.

  Lemma app_tail_case : forall (xs ys ys' : list A) x y,
    xs ++ x :: nil = ys ++ y :: ys' ->
    ys' = nil /\ x = y /\ xs = ys \/
    exists ys'', xs = ys ++ y :: ys'' /\ ys' = ys'' ++ x :: nil.
  Proof.
    intros * Heq.
    assert (Hcase: ys' = nil \/ exists ys'' y'', ys' = ys'' ++ y'' :: nil).
    { clear; induction ys'; auto.
      intuition (subst; eauto using app_nil_l).
      destruct H as (? & ? & ?); subst.
      eauto using app_comm_cons.
    }
    destruct Hcase as [? | (? & ? & ?)]; subst.
    - apply app_inj_tail in Heq; intuition auto.
    - rewrite app_comm_cons, app_assoc in Heq.
      apply app_inj_tail in Heq; intuition (subst; eauto).
  Qed.

  Lemma in_app_case : forall (xs ys xs' ys' : list A) x,
    xs ++ ys = xs' ++ x :: ys' ->
    (In x ys /\ exists zs, ys = zs ++ x :: ys') \/ (In x xs /\ exists zs, xs = xs' ++ x :: zs).
  Proof.
    induction xs; cbn; intros * Heq; subst; eauto.
    - rewrite in_app_iff; cbn; intuition eauto.
    - destruct xs'; inj; cbn; eauto.
      edestruct IHxs as [(? & ? & ?) | (? & ? & ?)]; eauto; subst; eauto.
  Qed.

  Lemma cons_app_single : forall (xs ys : list A) x,
    xs ++ x :: ys = (xs ++ x :: nil) ++ ys.
  Proof. intros; rewrite <- app_assoc; auto. Qed.

  Lemma combine_map_fst {B C} : forall (xs : list A) (ys : list B) (f : A -> C),
    combine (map f xs) ys = map (fun '(x, y) => (f x, y)) (combine xs ys).
  Proof.
    induction xs; intros *; cbn; auto.
    destruct ys; cbn; auto.
    f_equal; auto.
  Qed.

End ListFacts.

Local Open Scope monad_scope.
Local Open Scope Z.

Lemma div_plus : forall x y z w,
  x mod z = 0 ->
  0 < w ->
  0 <= y < z ->
  (x + y) / (z * w) = x / (z * w).
Proof.
  intros * Hmod ? ?.
  rewrite Z.mod_divide in Hmod by lia.
  destruct Hmod as (x' & ?); subst.
  rewrite <- Z.div_div, Z.div_add_l by lia.
  rewrite (Z.mul_comm z w), Z.div_mul_cancel_r by lia.
  now rewrite (Z.div_small y z), Z.add_0_r by lia.
Qed.

Definition lex_lt (p1 p2 : Z * Z) : Prop :=
  let (x1, y1) := p1 in let (x2, y2) := p2 in
  (x1 < x2 \/ x1 = x2 /\ y1 < y2)%Z.
Local Infix "<l" := lex_lt (at level 70).

Definition lex_le (p1 p2 : Z * Z) : Prop :=
  p1 = p2 \/ p1 <l p2 .
Local Infix "<=l" := lex_le (at level 70).

(* Weaker pre condition using trace_incl instead of eutt. *)
Definition getchar_pre' (m : mem) (witness : byte -> IO_itree) (z : IO_itree) :=
  let k := witness in trace_incl (r <- read stdin;; k r) z.

(* CertiKOS specs must terminate. Could get blocking version back by
   wrapping getchar in a loop. *)
Definition getchar_post' (m0 m : mem) r (witness : (byte -> IO_itree) * IO_itree) (z : @IO_itree (@IO_event nat)) :=
  m0 = m /\
    (* Success *)
    ((0 <= Int.signed r <= two_p 8 - 1 /\ let (k, _) := witness in z = k (Byte.repr (Int.signed r))) \/
    (* No character to read *)
    (Int.signed r = -1 /\ let (_, z0) := witness in z = z0)).

(** Traces *)
Definition ostrace := list IOEvent.

Definition IOEvent_eq (e1 e2 : IOEvent) : {e1 = e2} + {e1 <> e2} :=
  ltac:(repeat decide equality).

Definition trace_event_rtype (e : IOEvent) :=
  match e with
  | IOEvRecv _ _ _ => void
  | IOEvSend _ _ => void
  | IOEvGetc _ _ _ => byte
  | IOEvPutc _ _ => unit
  end.

Definition io_event_of_io_tevent (e : IOEvent)
  : option (IO_event (trace_event_rtype e) * (trace_event_rtype e)) :=
  match e with
  | IOEvRecv _ _ _ => None
  | IOEvSend _ _ => None
  | IOEvGetc _ _ r => Some (ERead stdin, Byte.repr r)
  | IOEvPutc _ r => Some (EWrite stdout (Byte.repr r), tt)
  end.

Fixpoint trace_of_ostrace (t : ostrace) : @trace IO_event unit :=
  match t with
  | nil => TEnd
  | e :: t' =>
      match io_event_of_io_tevent e with
      | Some (e', r) => TEventResponse e' r (trace_of_ostrace t')
      | _ => trace_of_ostrace t'
      end
  end.

(** Trace Invariants *)
Section Invariants.

  Definition get_sys_ret (st : RData) :=
    let curid := ZMap.get st.(CPU_ID) st.(cid) in
    ZMap.get U_EBX (ZMap.get curid st.(uctxt)).

  Definition get_sys_arg1 (st : RData) :=
    let curid := ZMap.get st.(CPU_ID) st.(cid) in
    ZMap.get U_EBX (ZMap.get curid st.(uctxt)).

  Definition get_sys_arg2 (st : RData) :=
    let curid := ZMap.get st.(CPU_ID) st.(cid) in
    ZMap.get U_ESI (ZMap.get curid st.(uctxt)).

  Fixpoint compute_console' (tr : ostrace) : list (Z * Z * nat) :=
    match tr with
    | nil => nil
    | ev :: tr' =>
      let cons := compute_console' tr' in
      match ev with
      | IOEvRecv logIdx strIdx c =>
        let cons' := if Zlength cons <? CONS_BUFFER_MAX_CHARS then cons else tl cons in
        cons' ++ (c, logIdx, strIdx) :: nil
      | IOEvGetc _ _ _ => tl cons
      | _ => cons
      end
    end.
  Definition compute_console tr := compute_console' (rev tr).

  (* Everything in the trace was put there by the serial device. *)
  Definition valid_trace_serial tr lrx :=
    forall logIdx strIdx c pre post,
      tr = pre ++ IOEvRecv logIdx strIdx c :: post ->
      logIdx < lrx - 1 /\
      match SerialEnv logIdx with
      | SerialRecv str => nth_error str strIdx = Some c
      | _ => False
      end.

  (* OS reads are ordered lexicographically by logIdx and strIdx. *)
  Definition valid_trace_ordered tr :=
    forall post mid pre logIdx strIdx c logIdx' strIdx' c',
      tr = pre ++ IOEvRecv logIdx strIdx c :: mid ++ IOEvRecv logIdx' strIdx' c' :: post ->
      (logIdx, Z.of_nat strIdx) <l (logIdx', Z.of_nat strIdx').

  (* Every user read has a matching OS read earlier in the trace. *)
  Definition valid_trace_user tr :=
    forall logIdx strIdx c pre post,
      tr = pre ++ IOEvGetc logIdx strIdx c :: post ->
      In (IOEvRecv logIdx strIdx c) pre /\ hd_error (compute_console pre) = Some (c, logIdx, strIdx).

  (* Every read event in the trace is unique. *)
  Definition valid_trace_unique (tr : ostrace) :=
    let tr' := filter (fun ev =>
      match ev with | IOEvRecv _ _ _ | IOEvGetc _ _ _ => true | _ => false end) tr in
    NoDup tr'.

  (* The console matches compute_console. *)
  Definition valid_trace_console tr cons := cons = compute_console tr.

  (* All trace invariants hold. *)
  Record valid_trace (st : RData) := {
    vt_trace_serial : valid_trace_serial st.(io_log) st.(com1).(l1);
    vt_trace_ordered : valid_trace_ordered st.(io_log);
    vt_trace_user : valid_trace_user st.(io_log);
    vt_trace_unique : valid_trace_unique st.(io_log);
    vt_trace_console : valid_trace_console st.(io_log) st.(console).(cons_buf);
  }.

  (* Console entries are ordered by logIdx and strIdx *)
  Lemma valid_trace_ordered_snoc : forall tr ev,
    valid_trace_ordered (tr ++ ev :: nil) ->
    valid_trace_ordered tr.
  Proof.
    unfold valid_trace_ordered.
    intros * Hvalid * ->; eapply Hvalid.
    do 2 (rewrite <- app_assoc, <- app_comm_cons); auto.
  Qed.

  Lemma valid_trace_ordered_app : forall tr' tr,
    valid_trace_ordered (tr ++ tr') ->
    valid_trace_ordered tr.
  Proof.
    induction tr'; cbn; intros *.
    - rewrite app_nil_r; auto.
    - rewrite cons_app_single.
      eauto using valid_trace_ordered_snoc.
  Qed.

  Local Hint Resolve valid_trace_ordered_snoc valid_trace_ordered_app.

  Lemma in_console_in_trace' : forall tr logIdx strIdx c,
    In (c, logIdx, strIdx) (compute_console' tr) ->
    In (IOEvRecv logIdx strIdx c) tr.
  Proof.
    induction tr as [| ev tr]; cbn; intros * Hin; eauto.
    destruct ev; auto using in_tail.
    rewrite in_app_iff in Hin; cbn in Hin.
    intuition (inj; auto); right.
    destruct (_ <? _); auto using in_tail.
  Qed.

  Corollary in_console_in_trace : forall tr logIdx strIdx c,
    In (c, logIdx, strIdx) (compute_console tr) ->
    In (IOEvRecv logIdx strIdx c) tr.
  Proof.
    unfold compute_console; intros * Hin.
    apply in_rev.
    apply in_console_in_trace'; auto.
  Qed.

  Lemma console_trace_same_order' : forall tr pre mid post logIdx strIdx c logIdx' strIdx' c',
    compute_console' tr = pre ++ (c, logIdx, strIdx) :: mid ++ (c', logIdx', strIdx') :: post ->
    exists pre' mid' post',
      tr = post' ++ IOEvRecv logIdx' strIdx' c' :: mid' ++ IOEvRecv logIdx strIdx c :: pre'.
  Proof.
    induction tr as [| ev tr]; cbn; intros * Hcons;
      [contradict Hcons; auto using app_cons_not_nil |].
    destruct ev; cbn in Hcons;
      try solve [edestruct IHtr as (? & ? & ? & ?); eauto; subst; eauto using app_comm_cons].
    - rewrite app_comm_cons, app_assoc in Hcons.
      destruct @app_tail_case with (1 := Hcons) as [(? & ? & Hcons') | (? & Hcons' & ?)]; inj; subst;
        destruct (_ <? _).
      + assert (Hin: In (c, logIdx, strIdx) (compute_console' tr)).
        { rewrite Hcons', in_app_iff; cbn; auto. }
        apply in_console_in_trace' in Hin.
        apply in_split in Hin; destruct Hin as (? & ? & ?); subst; eauto using app_nil_l.
      + apply tail_not_nil_has_head in Hcons'; auto using app_cons_not_nil.
        destruct Hcons' as (? & Hcons').
        rewrite app_comm_cons in Hcons'.
        assert (Hin: In (c, logIdx, strIdx) (compute_console' tr)).
        { rewrite Hcons', in_app_iff; cbn; auto. }
        apply in_console_in_trace' in Hin.
        apply in_split in Hin; destruct Hin as (? & ? & Heq); subst; eauto using app_nil_l.
      + rewrite <- app_assoc, <- app_comm_cons in Hcons'.
        edestruct IHtr as (? & ? & ? & Heq'); eauto; subst; eauto using app_comm_cons.
      + apply tail_not_nil_has_head in Hcons'; auto using app_cons_not_nil.
        destruct Hcons' as (? & Hcons').
        rewrite <- app_assoc, <- app_comm_cons in Hcons'.
        rewrite app_comm_cons in Hcons'.
        edestruct IHtr as (? & ? & ? & Heq); eauto; subst; eauto using app_comm_cons.
    - assert (Hcons': exists el,
        compute_console' tr = el :: pre ++ (c, logIdx, strIdx) :: mid ++ (c', logIdx', strIdx') :: post).
      { destruct (compute_console' tr); cbn in Hcons; subst; eauto.
        contradict Hcons; auto using app_cons_not_nil.
      }
      destruct Hcons' as (? & Hcons').
      rewrite app_comm_cons in Hcons'; eauto.
        edestruct IHtr as (? & ? & ? & Heq); eauto; subst; eauto using app_comm_cons.
  Qed.

  Corollary console_tl_trace_same_order' : forall tr logIdx strIdx c logIdx' strIdx' c',
    hd_error (compute_console' tr) = Some (c, logIdx, strIdx) ->
    hd_error (tl (compute_console' tr)) = Some (c', logIdx', strIdx') ->
    exists pre' mid' post',
      tr = post' ++ IOEvRecv logIdx' strIdx' c' :: mid' ++ IOEvRecv logIdx strIdx c :: pre'.
  Proof.
    intros * Hcons Hcons'.
    destruct (compute_console' tr) as [| ? cons] eqn:Heq; cbn in Hcons, Hcons'; [easy |]; inj.
    destruct cons as [| ? cons'] eqn:Heq'; cbn in Hcons'; [easy |]; inj.
    eapply console_trace_same_order'.
    instantiate (1 := cons'); repeat instantiate (1 := nil); eauto.
  Qed.

  Lemma compute_console_ordered' : forall tr ev logIdx strIdx c logIdx' strIdx' c',
    let cons := compute_console' tr in
    let cons' := compute_console' (ev :: tr) in
    valid_trace_ordered (rev tr ++ ev :: nil) ->
    hd_error cons = Some (c, logIdx, strIdx) ->
    hd_error cons' = Some (c', logIdx', strIdx') ->
    match ev with
    | IOEvGetc _ _ _ => (logIdx, Z.of_nat strIdx) <l (logIdx', Z.of_nat strIdx')
    | _ => (logIdx, Z.of_nat strIdx) <=l (logIdx', Z.of_nat strIdx')
    end.
  Proof.
    unfold lex_le, lex_lt; intros * Horder Hcons Hcons'.
    destruct ev; cbn in Hcons';
      try solve [rewrite Hcons in Hcons'; inj; auto].
    - destruct (_ <? _).
      + erewrite hd_error_app in Hcons'; eauto; inj; auto.
      + destruct (hd_error_app_case (tl (compute_console' tr)) (c0, logIdx0, strIdx0)) as [Heq | Heq];
          rewrite Heq in Hcons'; clear Heq.
        * edestruct console_tl_trace_same_order' as (? & ? & ? & Heq); eauto; subst.
          simpl_rev_in Horder.
          right; eapply Horder; eauto.
        * cbn in Hcons'; inj.
          apply hd_error_in in Hcons.
          apply in_console_in_trace' in Hcons.
          apply in_split in Hcons; destruct Hcons as (? & ? & ?); subst.
          simpl_rev_in Horder.
          right; eapply Horder; eauto.
    - edestruct console_tl_trace_same_order' as (? & ? & ? & Heq); eauto; subst.
      simpl_rev_in Horder.
      eapply Horder; eauto.
  Qed.

  Lemma compute_console_user_idx_increase' : forall post pre logIdx strIdx c logIdx' strIdx' c',
    let tr := post ++ IOEvGetc logIdx strIdx c :: pre in
    let cons := compute_console' pre in
    let cons' := compute_console' tr in
    valid_trace_ordered (rev tr) ->
    hd_error cons = Some (c, logIdx, strIdx) ->
    hd_error cons' = Some (c', logIdx', strIdx') ->
    (logIdx, Z.of_nat strIdx) <l (logIdx', Z.of_nat strIdx').
  Proof.
    unfold lex_le, lex_lt; induction post as [| ev post]; intros * Horder Hcons Hcons'; simpl_rev_in Horder.
    - eapply compute_console_ordered' in Hcons; eauto.
      cbn in Hcons, Hcons'; auto.
    - assert (Hcase:
        (exists logIdx'' strIdx'' c'',
          hd_error (compute_console' (post ++ IOEvGetc logIdx strIdx c :: pre)) = Some (c'', logIdx'', strIdx'')) \/
        ev = IOEvRecv logIdx' strIdx' c' /\ compute_console' (post ++ IOEvGetc logIdx strIdx c :: pre) = nil).
      { cbn in Hcons'; destruct ev; eauto.
        - destruct (compute_console' (post ++ _ :: pre)) as [| ((? & ?) & ?) ?] eqn:?; cbn; eauto.
          right; destruct (_ <? _); cbn in Hcons'; inj; eauto.
        - eapply hd_error_tl in Hcons'.
          destruct Hcons' as (((? & ?) & ?) & ?); eauto.
      }
      destruct Hcase as [(logIdx'' & strIdx'' & c'' & Hcons'') | (? & Hcons'')]; subst.
      + enough ((logIdx, Z.of_nat strIdx) <l (logIdx'', Z.of_nat strIdx'')
                /\ (logIdx'', Z.of_nat strIdx'') <=l (logIdx', Z.of_nat strIdx')).
        { unfold lex_le, lex_lt in *. intuition (inj; auto; lia). }
        unfold lex_le, lex_lt; split.
        * eapply IHpost with (pre := pre); simpl_rev; eauto.
          eapply valid_trace_ordered_snoc.
          rewrite <- app_assoc, <- app_comm_cons; eauto.
        * rewrite <- app_comm_cons in Hcons'.
          eapply compute_console_ordered' in Hcons'; eauto; simpl_rev; eauto.
          destruct ev; auto.
      + apply hd_error_in in Hcons.
        apply in_console_in_trace' in Hcons.
        apply in_split in Hcons; destruct Hcons as (? & ? & ?); subst.
        simpl_rev_in Horder.
        rewrite (app_comm_cons _ _ (IOEvGetc _ _ _)) in Horder.
        rewrite app_assoc in Horder.
        eapply Horder; eauto.
  Qed.

  Corollary compute_console_user_idx_increase : forall pre post logIdx strIdx c logIdx' strIdx' c',
    let tr := pre ++ IOEvGetc logIdx strIdx c :: post in
    let cons := compute_console pre in
    let cons' := compute_console tr in
    valid_trace_ordered tr ->
    hd_error cons = Some (c, logIdx, strIdx) ->
    hd_error cons' = Some (c', logIdx', strIdx') ->
    (logIdx, Z.of_nat strIdx) <l (logIdx', Z.of_nat strIdx').
  Proof.
    unfold compute_console; intros *; simpl_rev; intros Horder Hcons Hcons'.
    eapply compute_console_user_idx_increase'; eauto.
    simpl_rev; auto.
  Qed.

  Lemma console_len' : forall tr,
    Zlength (compute_console' tr) <= CONS_BUFFER_MAX_CHARS.
  Proof.
    induction tr as [| ev tr]; cbn; try lia.
    destruct ev; cbn; auto.
    - destruct (_ <? _) eqn:Hlt; [rewrite Z.ltb_lt in Hlt | rewrite Z.ltb_nlt in Hlt];
        rewrite Zlength_app, Zlength_cons, Zlength_nil; try lia.
      rewrite Zlength_tail_strong; try lia.
      intros Hcons; rewrite Hcons in *; cbn in *; lia.
    - etransitivity; [apply Zlength_tail |]; auto.
  Qed.

  Corollary console_len : forall tr,
    Zlength (compute_console tr) <= CONS_BUFFER_MAX_CHARS.
  Proof. intros; apply console_len'. Qed.

  (* mkRecvEvents Lemmas *)
  Lemma combine_NoDup {A B} : forall (xs : list A) (ys : list B),
    NoDup xs -> NoDup (combine xs ys).
  Proof.
    induction xs; intros * Hnodup; cbn in *; [constructor | inv Hnodup].
    destruct ys; cbn; constructor; auto.
    intros Hin; apply in_combine_l in Hin; easy.
  Qed.

  Lemma mkRecvEvents_NoDup : forall logIdx cs,
    NoDup (mkRecvEvents logIdx cs).
  Proof.
    unfold mkRecvEvents, enumerate; intros.
    apply FinFun.Injective_map_NoDup; auto using combine_NoDup, seq_NoDup.
    red; intros (? & ?) (? & ?); intros; inj; auto.
  Qed.

  Lemma Zlength_enumerate {A} : forall (xs : list A),
    Zlength (enumerate xs) = Zlength xs.
  Proof.
    unfold enumerate; intros.
    rewrite conclib.Zlength_combine, !Zlength_correct, seq_length; lia.
  Qed.

  Lemma seq_nth_app : forall len start n pre post,
    seq start len = pre ++ n :: post ->
    n = (start + length pre)%nat.
  Proof.
    intros * Heq.
    enough (n = nth (length pre) (seq start len) O); subst.
    { rewrite Heq, app_nth2, Nat.sub_diag, seq_nth; auto; cbn.
      rewrite <- (seq_length len start), Heq, app_length; cbn; lia.
    }
    rewrite Heq, app_nth2, Nat.sub_diag; auto.
  Qed.

  Lemma enumerate_length {A} : forall (xs : list A) n x pre post,
    enumerate xs = pre ++ (n, x) :: post ->
    n = length pre.
  Proof.
    unfold enumerate; intros * Heq.
    apply (f_equal (map fst)) in Heq.
    rewrite conclib.combine_fst, map_app in Heq; cbn in Heq.
    apply seq_nth_app in Heq; subst; cbn; auto using map_length.
    rewrite <- Nat2Z.id, <- Zlength_length; rewrite <- Zlength_correct.
    - rewrite !Zlength_correct, seq_length; auto.
    - apply Zlength_nonneg.
  Qed.

  Lemma mkRecvEvents_strIdx : forall cs logIdx strIdx c pre post,
    mkRecvEvents logIdx cs = pre ++ IOEvRecv logIdx strIdx c :: post ->
    strIdx = length pre.
  Proof.
    unfold mkRecvEvents; intros * Heq.
    apply (f_equal (map (fun ev =>
      match ev with
      | IOEvRecv _ sidx c => (sidx, c)
      | _ => (O, 0) (* impossible *)
      end))) in Heq.
    rewrite List.map_map, map_app in Heq; cbn in Heq.
    assert (Henum: map
        (fun x : nat * Z =>
         match (let (i, c) := x in IOEvRecv logIdx i c) with
         | IOEvRecv _ sidx c => (sidx, c)
         | _ => (O, 0)
         end) (enumerate cs) = enumerate cs).
    { clear.
      induction (enumerate cs) as [| ev ?]; cbn; auto.
      destruct ev; cbn; f_equal; auto.
    }
    rewrite Henum in Heq.
    apply enumerate_length in Heq; subst; auto using map_length.
  Qed.

  Corollary mkRecvEvents_ordered : forall cs logIdx strIdx c strIdx' c' pre mid post,
    mkRecvEvents logIdx cs = pre ++ IOEvRecv logIdx strIdx c :: mid ++ IOEvRecv logIdx strIdx' c' :: post ->
    Z.of_nat strIdx < Z.of_nat strIdx'.
  Proof.
    intros * Heq.
    pose proof Heq as Heq'.
    rewrite app_comm_cons, app_assoc in Heq'.
    apply mkRecvEvents_strIdx in Heq; apply mkRecvEvents_strIdx in Heq'; subst.
    rewrite app_length; cbn; lia.
  Qed.

  Lemma mkRecvEvents_cons : forall cs c logIdx,
    mkRecvEvents logIdx (c :: cs) =
    IOEvRecv logIdx O c :: map (fun ev =>
      match ev with
      | IOEvRecv lidx sidx c' => IOEvRecv lidx (S sidx) c'
      | _ => IOEvRecv 0 O 0 (* impossible *)
      end) (mkRecvEvents logIdx cs).
  Proof.
    cbn; intros *; f_equal.
    unfold mkRecvEvents, enumerate.
    rewrite <- seq_shift.
    rewrite combine_map_fst, !List.map_map.
    induction (combine (seq _ _) cs) as [| ev ?]; cbn; auto.
    f_equal; auto.
    destruct ev; auto.
  Qed.

  Lemma in_mkRecvEvents : forall cs ev logIdx,
    In ev (mkRecvEvents logIdx cs) ->
    exists strIdx c,
      nth_error cs strIdx = Some c /\
      nth_error (mkRecvEvents logIdx cs) strIdx = Some ev /\
      ev = IOEvRecv logIdx strIdx c.
  Proof.
    induction cs; intros * Hin; try easy.
    rewrite mkRecvEvents_cons in Hin; cbn in Hin.
    destruct Hin as [? | Hin]; subst.
    - repeat (esplit; eauto); cbn; auto.
    - rewrite mkRecvEvents_cons.
      apply Coqlib.list_in_map_inv in Hin; destruct Hin as (? & ? & Hin); subst.
      eapply IHcs in Hin.
      destruct Hin as (? & ? & ? & ? & ?); subst.
      repeat (esplit; eauto); cbn; auto.
      prename (nth_error (mkRecvEvents _ _) _ = _) into Hnth.
      eapply map_nth_error in Hnth; rewrite Hnth; auto.
  Qed.

  Lemma compute_console_app_space' : forall evs tr,
    let cons := compute_console' tr in
    (forall ev, In ev evs -> exists logIdx strIdx c, ev = IOEvRecv logIdx strIdx c) ->
    Zlength cons + Zlength evs <= CONS_BUFFER_MAX_CHARS ->
    compute_console' (evs ++ tr) =
    cons ++ rev (map (fun ev =>
      match ev with
      | IOEvRecv logIdx strIdx c => (c, logIdx, strIdx)
      | _ => (0, 0, O) (* impossible *)
      end) evs).
  Proof.
    induction evs as [| ev evs]; cbn -[Zlength]; intros * Hall Hlen; auto using app_nil_r.
    rewrite Zlength_cons in Hlen.
    edestruct Hall as (? & ? & ? & ?); eauto; subst.
    destruct (_ <? _) eqn:Hlt; auto.
    - rewrite IHevs; auto using app_assoc; lia.
    - rewrite Z.ltb_nlt in Hlt.
      rewrite IHevs in Hlt; auto; try lia.
      rewrite Zlength_app, Zlength_rev, Zlength_map in Hlt; lia.
  Qed.

  Corollary compute_console_app_space : forall evs tr,
    let cons := compute_console tr in
    (forall ev, In ev evs -> exists logIdx strIdx c, ev = IOEvRecv logIdx strIdx c) ->
    Zlength cons + Zlength evs <= CONS_BUFFER_MAX_CHARS ->
    compute_console (tr ++ evs) =
    cons ++ (map (fun ev =>
      match ev with
      | IOEvRecv logIdx strIdx c => (c, logIdx, strIdx)
      | _ => (0, 0, O) (* impossible *)
      end) evs).
  Proof.
    unfold compute_console; intros.
    rewrite rev_app_distr, compute_console_app_space'.
    - rewrite map_rev, rev_involutive; auto.
    - intros * Hin; rewrite <- in_rev in Hin; auto.
    - rewrite Zlength_rev; auto.
  Qed.

  Lemma compute_console_app_no_space' : forall evs tr,
    let cons := compute_console' tr in
    let skip := Zlength cons + Zlength evs - CONS_BUFFER_MAX_CHARS in
    (forall ev, In ev evs -> exists logIdx strIdx c, ev = IOEvRecv logIdx strIdx c) ->
    Zlength cons <= CONS_BUFFER_MAX_CHARS ->
    Zlength cons + Zlength evs > CONS_BUFFER_MAX_CHARS ->
    compute_console' (evs ++ tr) =
    skipn (Z.to_nat skip) (cons ++ rev (map (fun ev =>
      match ev with
      | IOEvRecv logIdx strIdx c => (c, logIdx, strIdx)
      | _ => (0, 0, O) (* impossible *)
      end) evs)).
  Proof.
    induction evs as [| ev evs]; cbn -[Zlength]; intros * Hall Hmax Hlen.
    { cbn in *.
      replace (Zlength (compute_console' tr)) with CONS_BUFFER_MAX_CHARS by lia.
      cbn; auto using app_nil_r.
    }
    rewrite Zlength_cons in Hlen.
    edestruct Hall as (? & ? & ? & ?); eauto; subst.
    assert (Hcase:
      Zlength (compute_console' tr) + Zlength evs > CONS_BUFFER_MAX_CHARS
      \/ Zlength (compute_console' tr) + Zlength evs = CONS_BUFFER_MAX_CHARS) by lia.
    destruct Hcase as [? | Hlen'].
    - destruct (_ <? _) eqn:Hlt; auto.
      + rewrite Z.ltb_lt in Hlt.
        rewrite IHevs in Hlt; auto.
        rewrite Zlength_skipn, Zlength_app, Zlength_rev, Zlength_map in Hlt; lia.
      + rewrite Zlength_cons, IHevs; auto.
        assert (Hskip:
          Z.to_nat (Zlength (compute_console' tr) + Z.succ (Zlength evs) - CONS_BUFFER_MAX_CHARS)
          = S (Z.to_nat (Zlength (compute_console' tr) + Zlength evs - CONS_BUFFER_MAX_CHARS))).
        { rewrite <- Z2Nat.inj_succ by lia; f_equal; lia. }
        cbn in Hskip; rewrite Hskip, skipn_tl, <- tl_app; cbn.
        * rewrite <- Zskipn_app1 by (rewrite Zlength_app, Zlength_rev, Zlength_map; lia).
          rewrite app_assoc; auto.
        * intros Heq; apply (f_equal (@Zlength _)) in Heq; cbn in Heq.
          rewrite Zlength_skipn, Zlength_app, Zlength_rev, Zlength_map in Heq; lia.
    - rewrite compute_console_app_space'; auto; try lia.
      rewrite Zlength_app, Zlength_rev, Zlength_map.
      rewrite Hlen', Zlength_cons; cbn.
      assert (Hskip:
        Z.to_nat (Zlength (compute_console' tr) + Z.succ (Zlength evs) - CONS_BUFFER_MAX_CHARS)
        = S (Z.to_nat (Zlength (compute_console' tr) + Zlength evs - CONS_BUFFER_MAX_CHARS))).
      { rewrite <- Z2Nat.inj_succ by lia; f_equal; lia. }
      cbn in Hskip; rewrite Hskip, skipn_tl, Hlen', <- tl_app; cbn.
      + rewrite app_assoc; auto.
      + intros Heq; apply (f_equal (@Zlength _)) in Heq; cbn in Heq.
        rewrite Zlength_app, Zlength_rev, Zlength_map in Heq; lia.
  Qed.

  Corollary compute_console_app_no_space : forall evs tr,
    let cons := compute_console tr in
    let skip := Zlength cons + Zlength evs - CONS_BUFFER_MAX_CHARS in
    (forall ev, In ev evs -> exists logIdx strIdx c, ev = IOEvRecv logIdx strIdx c) ->
    Zlength cons <= CONS_BUFFER_MAX_CHARS ->
    Zlength cons + Zlength evs > CONS_BUFFER_MAX_CHARS ->
    compute_console (tr ++ evs) =
    skipn (Z.to_nat skip) (cons ++ (map (fun ev =>
      match ev with
      | IOEvRecv logIdx strIdx c => (c, logIdx, strIdx)
      | _ => (0, 0, O) (* impossible *)
      end) evs)).
  Proof.
    unfold compute_console; intros.
    rewrite rev_app_distr, compute_console_app_no_space'; auto.
    - rewrite map_rev, rev_involutive, Zlength_rev; auto.
    - intros * Hin; rewrite <- in_rev in Hin; auto.
    - rewrite Zlength_rev; auto.
  Qed.

  (** Trace Invariants Preserved *)
  (* Specs:
       serial_intr_enable_spec
       serial_intr_disable_spec
       thread_serial_intr_enable_spec
       thread_serial_intr_disable_spec
       uctx_set_retval1_spec
       uctx_set_errno_spec
       serial_putc_spec
       cons_buf_read_spec
       cons_buf_read_loop_spec
       thread_cons_buf_read_spec
       thread_serial_putc_spec
       thread_cons_buf_read_loop_spec
       sys_getc_spec
       sys_putc_spec
       sys_getcs_spec
  *)
  Context `{ThreadsConfigurationOps}.

  Lemma valid_trace_tx_event : forall st ev,
    match ev with
    | IOEvSend _ _ | IOEvPutc _ _ => True
    | _ => False
    end ->
    valid_trace st ->
    valid_trace (st {io_log : st.(io_log) ++ ev :: nil}).
  Proof.
    destruct ev; try easy; intros _ Hvalid; inv Hvalid; constructor; red; destruct st; cbn in *.
    - intros * Heq.
      apply in_app_case in Heq; cbn in Heq; intuition (try easy).
      all: destruct H2; subst; eapply vt_trace_serial0; eauto.
    - intros * Heq.
      rewrite app_comm_cons, app_assoc in Heq.
      apply in_app_case in Heq; cbn in Heq; intuition (try easy).
      destruct H2; subst; eauto. eapply vt_trace_ordered0; rewrite app_comm_cons, app_assoc; eauto.
    - intros * Heq.
      apply in_app_case in Heq; cbn in Heq; intuition (try easy).
      all: destruct H2; subst; eapply vt_trace_user0; eauto.
    - rewrite conclib.filter_app, app_nil_r; auto.
    - simpl_rev; cbn; auto.
    - intros * Heq.
      apply in_app_case in Heq; cbn in Heq; intuition (try easy).
      all: destruct H2; subst; eapply vt_trace_serial0; eauto.
    - intros * Heq.
      rewrite app_comm_cons, app_assoc in Heq.
      apply in_app_case in Heq; cbn in Heq; intuition (try easy).
      destruct H2; subst; eauto. eapply vt_trace_ordered0; rewrite app_comm_cons, app_assoc; eauto.
    - intros * Heq.
      apply in_app_case in Heq; cbn in Heq; intuition (try easy).
      all: destruct H2; subst; eapply vt_trace_user0; eauto.
    - rewrite conclib.filter_app, app_nil_r; auto.
    - simpl_rev; cbn; auto.
  Qed.

  Lemma cons_intr_aux_preserve_valid_trace : forall st st',
    valid_trace st ->
    cons_intr_aux st = Some st' ->
    valid_trace st'.
  Proof.
    unfold cons_intr_aux; intros * Hvalid Hspec; destruct_spec Hspec.
    - prename (Coqlib.zeq _ _ = _) into Htmp; clear Htmp.
      destruct st; inv Hvalid; constructor; cbn in *; subst; red; cbn in *.
      + (* valid_trace_serial *)
        intros * Heq.
        rewrite Zlength_map.
        pose proof (Zlength_nonneg (enumerate RxBuf)).
        apply in_app_case in Heq.
        destruct Heq as [(Hin & ? & ?) | (? & ? & ?)]; subst.
        * eapply in_mkRecvEvents in Hin.
          destruct Hin as (? & ? & ? & ? & ?); inj.
          prename (SerialEnv _ = _) into Henv.
          rewrite Henv; split; auto; lia.
        * edestruct vt_trace_serial0; eauto.
          split; auto; lia.
      + (* valid_trace_ordered *)
        intros * Heq.
        pose proof Heq as Hcase.
        rewrite app_comm_cons, app_assoc in Hcase.
        apply in_app_case in Hcase.
        destruct Hcase as [(Hin & ? & _) | (? & ? & ?)]; subst.
        * eapply in_mkRecvEvents in Hin.
          destruct Hin as (? & ? & ? & ? & ?); inj.
          apply in_app_case in Heq.
          destruct Heq as [(Hin' & ? & ?) | (? & ? & ?)]; subst.
          -- eapply in_mkRecvEvents in Hin'.
             destruct Hin' as (? & ? & ? & ? & ?); inj.
             prename (mkRecvEvents _ _ = _) into Heq'.
             apply mkRecvEvents_ordered in Heq'; auto.
          -- edestruct vt_trace_serial0; eauto.
        * edestruct vt_trace_ordered0; eauto.
          rewrite <- app_assoc, <- app_comm_cons; eauto.
      + (* valid_trace_user *)
        intros * Heq.
        apply in_app_case in Heq.
        destruct Heq as [(Hin & ? & ?) | (? & ? & ?)]; subst; eauto.
        eapply in_mkRecvEvents in Hin.
        destruct Hin as (? & ? & ? & ? & ?); inj; easy.
      + (* valid_trace_unique *)
        rewrite conclib.filter_app, conclib.NoDup_app_iff; repeat split;
          auto using mkRecvEvents_NoDup, conclib.NoDup_filter.
        intros *; rewrite !filter_In.
        intros (Hin & ?) (Hin' & ?).
        eapply in_mkRecvEvents in Hin'.
        destruct Hin' as (? & ? & ? & ? & ?); inj; subst.
        apply in_split in Hin; destruct Hin as (? & ? & ?); subst.
        edestruct vt_trace_serial0; eauto; lia.
      + (* valid_trace_console *)
        prename Coqlib.zle into Htmp; clear Htmp.
        prename (_ <= _) into Hle.
        destruct console; cbn in *.
        rewrite vt_trace_console0.
        rewrite vt_trace_console0, Zlength_app, Zlength_map in Hle.
        rewrite compute_console_app_space.
        * unfold mkRecvEvents; f_equal; rewrite List.map_map.
          clear; induction (enumerate _) as [| (? & ?) ?]; cbn; auto.
          rewrite IHl; auto.
        * intros * Hin.
          eapply in_mkRecvEvents in Hin.
          destruct Hin as (? & ? & ? & ? & ?); inj; subst; eauto.
        * unfold mkRecvEvents; rewrite Zlength_map; auto.
    - prename (Coqlib.zeq _ _ = _) into Htmp; clear Htmp.
      destruct st; inv Hvalid; constructor; cbn in *; subst; red; cbn in *.
      + (* valid_trace_serial *)
        intros * Heq.
        rewrite Zlength_map.
        pose proof (Zlength_nonneg (enumerate RxBuf)).
        apply in_app_case in Heq.
        destruct Heq as [(Hin & ? & ?) | (? & ? & ?)]; subst.
        * eapply in_mkRecvEvents in Hin.
          destruct Hin as (? & ? & ? & ? & ?); inj.
          prename (SerialEnv _ = _) into Henv.
          rewrite Henv; split; auto; lia.
        * edestruct vt_trace_serial0; eauto.
          split; auto; lia.
      + (* valid_trace_ordered *)
        intros * Heq.
        pose proof Heq as Hcase.
        rewrite app_comm_cons, app_assoc in Hcase.
        apply in_app_case in Hcase.
        destruct Hcase as [(Hin & ? & _) | (? & ? & ?)]; subst.
        * eapply in_mkRecvEvents in Hin.
          destruct Hin as (? & ? & ? & ? & ?); inj.
          apply in_app_case in Heq.
          destruct Heq as [(Hin' & ? & ?) | (? & ? & ?)]; subst.
          -- eapply in_mkRecvEvents in Hin'.
             destruct Hin' as (? & ? & ? & ? & ?); inj.
             prename (mkRecvEvents _ _ = _) into Heq'.
             apply mkRecvEvents_ordered in Heq'; auto.
          -- edestruct vt_trace_serial0; eauto.
        * edestruct vt_trace_ordered0; eauto.
          rewrite <- app_assoc, <- app_comm_cons; eauto.
      + (* valid_trace_user *)
        intros * Heq.
        apply in_app_case in Heq.
        destruct Heq as [(Hin & ? & ?) | (? & ? & ?)]; subst; eauto.
        eapply in_mkRecvEvents in Hin.
        destruct Hin as (? & ? & ? & ? & ?); inj; easy.
      + (* valid_trace_unique *)
        rewrite conclib.filter_app, conclib.NoDup_app_iff; repeat split;
          auto using mkRecvEvents_NoDup, conclib.NoDup_filter.
        intros *; rewrite !filter_In.
        intros (Hin & ?) (Hin' & ?).
        eapply in_mkRecvEvents in Hin'.
        destruct Hin' as (? & ? & ? & ? & ?); inj; subst.
        apply in_split in Hin; destruct Hin as (? & ? & ?); subst.
        edestruct vt_trace_serial0; eauto; lia.
      + (* valid_trace_console *)
        prename Coqlib.zle into Htmp; clear Htmp.
        prename (_ > _) into Hgt.
        destruct console; cbn in *.
        rewrite vt_trace_console0.
        rewrite Zlength_app, Zlength_map, Zlength_enumerate.
        rewrite vt_trace_console0, Zlength_app, Zlength_map in Hgt.
        rewrite compute_console_app_no_space; auto using console_len.
        * unfold mkRecvEvents.
          rewrite List.map_map, Zlength_map, Zlength_enumerate; do 2 f_equal.
          clear; induction (enumerate _) as [| (? & ?) ?]; cbn; auto.
          rewrite IHl; auto.
        * intros * Hin.
          eapply in_mkRecvEvents in Hin.
          destruct Hin as (? & ? & ? & ? & ?); inj; subst; eauto.
        * unfold mkRecvEvents; rewrite Zlength_map; auto.
  Qed.

  Lemma serial_intr_enable_aux_preserve_valid_trace : forall n st st',
    valid_trace st ->
    serial_intr_enable_aux n st = Some st' ->
    valid_trace st'.
  Proof.
    induction n; intros * Hvalid Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto.
    eapply IHn; [| eauto].
    eapply cons_intr_aux_preserve_valid_trace; eauto.
  Qed.

  Lemma serial_intr_enable_preserve_valid_trace : forall st st',
    valid_trace st ->
    serial_intr_enable_spec st = Some st' ->
    valid_trace st'.
  Proof.
    unfold serial_intr_enable_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    prename serial_intr_enable_aux into Hspec.
    eapply serial_intr_enable_aux_preserve_valid_trace in Hspec.
    2: destruct st; inv Hvalid; constructor; auto.
    destruct r; inv Hspec; constructor; auto.
  Qed.

  Lemma serial_intr_disable_aux_preserve_valid_trace : forall n mask st st',
    valid_trace st ->
    serial_intr_disable_aux n mask st = Some st' ->
    valid_trace st'.
  Proof.
    induction n; intros * Hvalid Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto.
    - eapply IHn; [| eauto].
      prename serial_intr into Hspec'; unfold serial_intr in Hspec'; destruct_spec Hspec'.
      destruct o.
      + enough (Hvalid': valid_trace (st {io_log : io_log st ++ IOEvSend 0 z :: nil}));
          auto using valid_trace_tx_event.
        destruct st; inv Hvalid'; constructor; cbn in *; auto.
        destruct com1; cbn in *; red; intros; subst; edestruct vt_trace_serial0; eauto.
        cbn; split; auto; lia.
      + rewrite app_nil_r; destruct st; inv Hvalid; constructor; cbn in *; auto.
        destruct com1; cbn in *; red; intros; subst; edestruct vt_trace_serial0; eauto.
        cbn; split; auto; lia.
    - eapply IHn; [| eauto].
      eapply cons_intr_aux_preserve_valid_trace; [| eauto].
      prename serial_intr into Hspec'; unfold serial_intr in Hspec'; destruct_spec Hspec'.
      destruct o.
      + enough (Hvalid': valid_trace (st {io_log : io_log st ++ IOEvSend 0 z :: nil}));
          auto using valid_trace_tx_event.
        destruct st; inv Hvalid'; constructor; cbn in *; auto.
        destruct com1; cbn in *; red; intros; subst; edestruct vt_trace_serial0; eauto.
        cbn; split; auto; lia.
      + rewrite app_nil_r; destruct st; inv Hvalid; constructor; cbn in *; auto.
        destruct com1; cbn in *; red; intros; subst; edestruct vt_trace_serial0; eauto.
        cbn; split; auto; lia.
  Qed.

  Lemma serial_intr_disable_preserve_valid_trace : forall st st',
    valid_trace st ->
    serial_intr_disable_spec st = Some st' ->
    valid_trace st'.
  Proof.
    unfold serial_intr_disable_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    prename serial_intr_disable_aux into Hspec.
    eapply serial_intr_disable_aux_preserve_valid_trace in Hspec.
    2: destruct st; inv Hvalid; constructor; auto.
    destruct r; inv Hspec; constructor; auto.
  Qed.

  Lemma thread_serial_intr_enable_preserve_valid_trace : forall st st',
    valid_trace st ->
    thread_serial_intr_enable_spec st = Some st' ->
    valid_trace st'.
  Proof.
    unfold thread_serial_intr_enable_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply serial_intr_enable_preserve_valid_trace; eauto.
  Qed.

  Lemma thread_serial_intr_disable_preserve_valid_trace : forall st st',
    valid_trace st ->
    thread_serial_intr_disable_spec st = Some st' ->
    valid_trace st'.
  Proof.
    unfold thread_serial_intr_disable_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply serial_intr_disable_preserve_valid_trace; eauto.
  Qed.

  Lemma uctx_set_retval1_preserve_valid_trace : forall st v st',
    valid_trace st ->
    uctx_set_retval1_spec v st = Some st' ->
    valid_trace st'.
  Proof.
    unfold uctx_set_retval1_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    destruct st; inv Hvalid; constructor; cbn in *; auto.
  Qed.

  Lemma uctx_set_errno_preserve_valid_trace : forall st e st',
    valid_trace st ->
    uctx_set_errno_spec e st = Some st' ->
    valid_trace st'.
  Proof.
    unfold uctx_set_errno_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    destruct st; inv Hvalid; constructor; cbn in *; auto.
  Qed.

  Lemma serial_putc_preserve_valid_trace : forall st c st' r,
    valid_trace st ->
    serial_putc_spec c st = Some (st', r) ->
    valid_trace st'.
  Proof.
    unfold serial_putc_spec; intros * Hvalid Hspec; destruct_spec Hspec; eauto.
    all: enough (Hvalid': valid_trace (st {io_log : io_log st ++ IOEvPutc l2 c :: nil}));
      auto using valid_trace_tx_event.
    all: destruct st; inv Hvalid'; constructor; cbn in *; subst; auto.
  Qed.

  Lemma cons_buf_read_preserve_valid_trace : forall st st' c,
    valid_trace st ->
    cons_buf_read_spec st = Some (st', c) ->
    valid_trace st'.
  Proof.
    unfold cons_buf_read_spec; intros * Hvalid Hspec; destruct_spec Hspec; eauto.
    prename (cons_buf _ = _) into Hcons.
    destruct st; inv Hvalid; constructor; cbn in *; subst; red.
    - (* valid_trace_serial *)
      intros * Heq.
      apply (f_equal (@rev _)) in Heq; simpl_rev_in Heq.
      destruct (rev post); cbn in Heq; inj; prename (rev _ = _) into Heq.
      apply (f_equal (@rev _)) in Heq; simpl_rev_in Heq; subst; eauto.
    - (* valid_trace_ordered *)
      intros * Heq.
      apply (f_equal (@rev _)) in Heq; simpl_rev_in Heq.
      destruct (rev post); cbn in Heq; inj; prename (rev _ = _) into Heq.
      apply (f_equal (@rev _)) in Heq; simpl_rev_in Heq; subst; eauto.
    - (* valid_trace_user *)
      intros * Heq.
      symmetry in Heq.
      apply (f_equal (@rev _)) in Heq; simpl_rev_in Heq.
      destruct (rev post); cbn in Heq; inj; prename (_ = rev _) into Heq;
        apply (f_equal (@rev _)) in Heq; simpl_rev_in Heq; subst; eauto.
      rewrite <- vt_trace_console0, Hcons; cbn; split; auto.
      apply in_console_in_trace.
      rewrite <- vt_trace_console0, Hcons; cbn; auto.
    - (* valid_trace_unique *)
      rewrite conclib.filter_app, conclib.NoDup_app_swap; cbn.
      constructor; auto; intros Hin.
      rewrite filter_In in Hin; destruct Hin as (Hin & _).
      apply in_split in Hin.
      destruct Hin as (post & pre & ?); subst.
      edestruct vt_trace_user0 as (Hin & Hhd); eauto.
      rewrite vt_trace_console0 in Hcons.
      apply (f_equal (@hd_error _)) in Hcons.
      eapply compute_console_user_idx_increase in Hcons; eauto.
      unfold lex_lt in Hcons; lia.
    - (* valid_trace_console *)
      destruct console; cbn in *; subst.
      red in vt_trace_console0.
      unfold compute_console in *; simpl_rev; cbn.
      rewrite <- vt_trace_console0; cbn; auto.
  Qed.

  Lemma cons_buf_read_loop_preserve_valid_trace : forall n st st' read addr read',
    valid_trace st ->
    cons_buf_read_loop_spec n read addr st = Some (st', read') ->
    valid_trace st'.
  Proof.
    induction n; intros * Hvalid Hspec; cbn [cons_buf_read_loop_spec] in Hspec; inj; auto.
    destruct_spec Hspec; inj; auto.
    eapply IHn in Hspec; eauto.
    prename cons_buf_read_spec into Hspec'.
    eapply cons_buf_read_preserve_valid_trace in Hspec'; auto.
    inv Hspec'; destruct r; constructor; auto.
  Qed.

  Lemma thread_cons_buf_read_preserve_valid_trace : forall st st' c,
    valid_trace st ->
    thread_cons_buf_read_spec st = Some (st', c) ->
    valid_trace st'.
  Proof.
    unfold thread_cons_buf_read_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply cons_buf_read_preserve_valid_trace; eauto.
  Qed.

  Lemma thread_serial_putc_preserve_valid_trace : forall st c st' r,
    valid_trace st ->
    thread_serial_putc_spec c st = Some (st', r) ->
    valid_trace st'.
  Proof.
    unfold thread_serial_putc_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply serial_putc_preserve_valid_trace; eauto.
  Qed.

  Lemma thread_cons_buf_read_loop_preserve_valid_trace : forall st st' len addr read,
    valid_trace st ->
    thread_cons_buf_read_loop_spec len addr st = Some (st', read) ->
    valid_trace st'.
  Proof.
    unfold thread_cons_buf_read_loop_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply cons_buf_read_loop_preserve_valid_trace; eauto.
  Qed.

  Lemma sys_getc_preserve_valid_trace : forall st st',
    valid_trace st ->
    sys_getc_spec st = Some st' ->
    valid_trace st'.
  Proof.
    unfold sys_getc_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply uctx_set_errno_preserve_valid_trace; [| eauto].
    eapply uctx_set_retval1_preserve_valid_trace; [| eauto].
    eapply thread_serial_intr_enable_preserve_valid_trace; [| eauto].
    eapply thread_cons_buf_read_preserve_valid_trace; [| eauto].
    eapply thread_serial_intr_disable_preserve_valid_trace; [| eauto].
    eauto.
  Qed.

  Lemma sys_putc_preserve_valid_trace : forall st st',
    valid_trace st ->
    sys_putc_spec st = Some st' ->
    valid_trace st'.
  Proof.
    unfold sys_putc_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply uctx_set_errno_preserve_valid_trace; [| eauto].
    eapply uctx_set_retval1_preserve_valid_trace; [| eauto].
    eapply thread_serial_intr_enable_preserve_valid_trace; [| eauto].
    eapply thread_serial_putc_preserve_valid_trace; [| eauto].
    eapply thread_serial_intr_disable_preserve_valid_trace; [| eauto].
    eauto.
  Qed.

  Lemma sys_getcs_preserve_valid_trace : forall st st',
    valid_trace st ->
    sys_getcs_spec st = Some st' ->
    valid_trace st'.
  Proof.
    unfold sys_getcs_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply uctx_set_errno_preserve_valid_trace; [| eauto].
    eapply uctx_set_retval1_preserve_valid_trace; [| eauto].
    eapply thread_serial_intr_enable_preserve_valid_trace; [| eauto].
    eapply thread_cons_buf_read_loop_preserve_valid_trace; [| eauto].
    eapply thread_serial_intr_disable_preserve_valid_trace; [| eauto].
    eauto.
  Qed.

  (* Memory is unchanged *)
  Lemma cons_intr_aux_mem_unchanged : forall st st',
    cons_intr_aux st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold cons_intr_aux; intros * Hspec; destruct_spec Hspec.
    all: destruct st; auto.
  Qed.

  Lemma serial_intr_enable_aux_mem_unchanged : forall n st st',
    serial_intr_enable_aux n st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    induction n; intros * Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto.
    etransitivity.
    eapply cons_intr_aux_mem_unchanged; eauto.
    eauto.
  Qed.

  Lemma serial_intr_enable_mem_unchanged : forall st st',
    serial_intr_enable_spec st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold serial_intr_enable_spec; intros * Hspec; destruct_spec Hspec.
    prename serial_intr_enable_aux into Hspec.
    eapply serial_intr_enable_aux_mem_unchanged in Hspec.
    destruct r, st; inv Hspec; auto.
  Qed.

  Lemma serial_intr_disable_aux_mem_unchanged : forall n mask st st',
    serial_intr_disable_aux n mask st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    induction n; intros * Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto.
    - etransitivity; [| eapply IHn; eauto].
      destruct st; auto.
    - etransitivity; [| eapply IHn; eauto].
      etransitivity; [| eapply cons_intr_aux_mem_unchanged; eauto].
      destruct st; auto.
  Qed.

  Lemma serial_intr_disable_mem_unchanged : forall st st',
    serial_intr_disable_spec st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold serial_intr_disable_spec; intros * Hspec; destruct_spec Hspec.
    prename serial_intr_disable_aux into Hspec.
    eapply serial_intr_disable_aux_mem_unchanged in Hspec.
    destruct r, st; inv Hspec; auto.
  Qed.

  Lemma thread_serial_intr_enable_mem_unchanged : forall st st',
    thread_serial_intr_enable_spec st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold thread_serial_intr_enable_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_intr_enable_mem_unchanged; eauto.
  Qed.

  Lemma thread_serial_intr_disable_mem_unchanged : forall st st',
    thread_serial_intr_disable_spec st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold thread_serial_intr_disable_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_intr_disable_mem_unchanged; eauto.
  Qed.

  Lemma uctx_set_retval1_mem_unchanged : forall st v st',
    uctx_set_retval1_spec v st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold uctx_set_retval1_spec; intros * Hspec; destruct_spec Hspec.
    destruct st; auto.
  Qed.

  Lemma uctx_set_errno_mem_unchanged : forall st e st',
    uctx_set_errno_spec e st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold uctx_set_errno_spec; intros * Hspec; destruct_spec Hspec.
    destruct st; auto.
  Qed.

  Lemma serial_putc_mem_unchanged : forall st c st' r,
    serial_putc_spec c st = Some (st', r) ->
    st.(HP) = st'.(HP).
  Proof.
    unfold serial_putc_spec; intros * Hspec; destruct_spec Hspec; eauto.
    all: destruct st; auto.
  Qed.

  Lemma cons_buf_read_mem_unchanged : forall st st' c,
    cons_buf_read_spec st = Some (st', c) ->
    st.(HP) = st'.(HP).
  Proof.
    unfold cons_buf_read_spec; intros * Hspec; destruct_spec Hspec; eauto.
    destruct st; auto.
  Qed.

  Lemma thread_cons_buf_read_mem_unchanged : forall st st' c,
    thread_cons_buf_read_spec st = Some (st', c) ->
    st.(HP) = st'.(HP).
  Proof.
    unfold thread_cons_buf_read_spec; intros * Hspec; destruct_spec Hspec.
    eapply cons_buf_read_mem_unchanged; eauto.
  Qed.

  Lemma thread_serial_putc_mem_unchanged : forall st c st' r,
    thread_serial_putc_spec c st = Some (st', r) ->
    st.(HP) = st'.(HP).
  Proof.
    unfold thread_serial_putc_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_putc_mem_unchanged; eauto.
  Qed.

  Lemma sys_getc_mem_unchanged : forall st st',
    sys_getc_spec st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold sys_getc_spec; intros * Hspec; destruct_spec Hspec.
    etransitivity; [| eapply uctx_set_errno_mem_unchanged; eauto].
    etransitivity; [| eapply uctx_set_retval1_mem_unchanged; eauto].
    etransitivity; [| eapply thread_serial_intr_enable_mem_unchanged; eauto].
    etransitivity; [| eapply thread_cons_buf_read_mem_unchanged; eauto].
    etransitivity; [| eapply thread_serial_intr_disable_mem_unchanged; eauto].
    eauto.
  Qed.

  Lemma sys_putc_mem_unchanged : forall st st',
    sys_putc_spec st = Some st' ->
    st.(HP) = st'.(HP).
  Proof.
    unfold sys_putc_spec; intros * Hspec; destruct_spec Hspec.
    etransitivity; [| eapply uctx_set_errno_mem_unchanged; eauto].
    etransitivity; [| eapply uctx_set_retval1_mem_unchanged; eauto].
    etransitivity; [| eapply thread_serial_intr_enable_mem_unchanged; eauto].
    etransitivity; [| eapply thread_serial_putc_mem_unchanged; eauto].
    etransitivity; [| eapply thread_serial_intr_disable_mem_unchanged; eauto].
    eauto.
  Qed.

  Lemma cons_buf_read_loop_mem_changed : forall n st st' read addr read',
    cons_buf_read_loop_spec n read addr st = Some (st', read') ->
    exists msg,
      Zlength msg = read' - Z.of_nat read /\
      Zlength msg <= Z.of_nat n /\
      FlatMem.storebytes st.(HP) addr (inj_bytes msg) = st'.(HP).
  Proof.
    induction n; intros * Hspec; cbn [cons_buf_read_loop_spec] in Hspec; inj.
    - rewrite Z.sub_diag.
      exists nil; cbn; repeat split; auto; lia.
    - destruct_spec Hspec; inj.
      + exists nil; cbn; repeat split; auto; lia.
      + eapply IHn in Hspec; eauto.
        cbn -[Z.of_nat] in Hspec; destruct Hspec as (msg & Hlen & ? & Hmem).
        exists (Byte.repr (Int.unsigned (Int.repr z)) :: msg).
        rewrite Zlength_cons, Hlen; cbn.
        repeat split; try lia.
        rewrite <- Hmem.
        destruct r; cbn in *.
        rewrite <- inj_bytes_encode_1; cbn; auto.
  Qed.

  Lemma thread_cons_buf_read_loop_mem_changed : forall st st' len addr read,
    thread_cons_buf_read_loop_spec len addr st = Some (st', read) ->
    exists msg,
      Zlength msg = read /\
      Zlength msg <= Z.max len 0 /\
      FlatMem.storebytes st.(HP) addr (inj_bytes msg) = st'.(HP).
  Proof.
    unfold thread_cons_buf_read_loop_spec; intros * Hspec; destruct_spec Hspec.
    apply cons_buf_read_loop_mem_changed in Hspec as (? & ? & ? & ?).
    repeat (esplit; eauto); try lia.
    rewrite <- Coqlib.Z_to_nat_max; auto.
  Qed.

  (* Virtual address mapping is unchanged *)
  Lemma cons_intr_aux_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    cons_intr_aux st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold cons_intr_aux; intros * Hspec; destruct_spec Hspec.
    all: destruct st; auto.
  Qed.

  Lemma serial_intr_enable_aux_pmap_unchanged : forall n st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    serial_intr_enable_aux n st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    induction n; intros * Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto; subst pid.
    edestruct cons_intr_aux_pmap_unchanged as (-> & ->); eauto.
  Qed.

  Lemma serial_intr_enable_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    serial_intr_enable_spec st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold serial_intr_enable_spec; intros * Hspec; destruct_spec Hspec.
    prename serial_intr_enable_aux into Hspec.
    eapply (serial_intr_enable_aux_pmap_unchanged _ _ _ vaddr) in Hspec.
    destruct r, st; inv Hspec; auto.
  Qed.

  Lemma serial_intr_disable_aux_pmap_unchanged : forall n mask st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    serial_intr_disable_aux n mask st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    induction n; intros * Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto; subst pid'.
    - edestruct IHn as (<- & <-); eauto.
      destruct st; auto.
    - edestruct IHn as (<- & <-); eauto.
      edestruct cons_intr_aux_pmap_unchanged as (<- & <-); eauto.
      destruct st; auto.
  Qed.

  Lemma serial_intr_disable_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    serial_intr_disable_spec st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold serial_intr_disable_spec; intros * Hspec; destruct_spec Hspec.
    prename serial_intr_disable_aux into Hspec.
    eapply (serial_intr_disable_aux_pmap_unchanged _ _ _ _ vaddr) in Hspec.
    destruct r, st; inv Hspec; auto.
  Qed.

  Lemma thread_serial_intr_enable_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    thread_serial_intr_enable_spec st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold thread_serial_intr_enable_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_intr_enable_pmap_unchanged; eauto.
  Qed.

  Lemma thread_serial_intr_disable_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    thread_serial_intr_disable_spec st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold thread_serial_intr_disable_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_intr_disable_pmap_unchanged; eauto.
  Qed.

  Lemma uctx_set_retval1_pmap_unchanged : forall st v st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    uctx_set_retval1_spec v st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold uctx_set_retval1_spec; intros * Hspec; destruct_spec Hspec.
    destruct st; auto.
  Qed.

  Lemma uctx_set_errno_pmap_unchanged : forall st e st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    uctx_set_errno_spec e st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold uctx_set_errno_spec; intros * Hspec; destruct_spec Hspec.
    destruct st; auto.
  Qed.

  Lemma serial_putc_pmap_unchanged : forall st c st' r vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    serial_putc_spec c st = Some (st', r) ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold serial_putc_spec; intros * Hspec; destruct_spec Hspec; eauto.
    all: destruct st; auto.
  Qed.

  Lemma cons_buf_read_pmap_unchanged : forall st st' c vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    cons_buf_read_spec st = Some (st', c) ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold cons_buf_read_spec; intros * Hspec; destruct_spec Hspec; eauto.
    destruct st; auto.
  Qed.

  Lemma cons_buf_read_loop_pmap_unchanged : forall n st st' read addr read' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    cons_buf_read_loop_spec n read addr st = Some (st', read') ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    induction n; intros * Hspec; cbn [cons_buf_read_loop_spec] in Hspec; inj; auto.
    destruct_spec Hspec; inj; auto.
    prename cons_buf_read_spec into Hspec'.
    eapply cons_buf_read_pmap_unchanged in Hspec'.
    eapply IHn in Hspec.
    destruct Hspec' as (-> & ->), Hspec as (<- & <-); destruct r; auto.
  Qed.

  Lemma thread_cons_buf_read_pmap_unchanged : forall st st' c vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    thread_cons_buf_read_spec st = Some (st', c) ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold thread_cons_buf_read_spec; intros * Hspec; destruct_spec Hspec.
    eapply cons_buf_read_pmap_unchanged; eauto.
  Qed.

  Lemma thread_serial_putc_pmap_unchanged : forall st c st' r vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    thread_serial_putc_spec c st = Some (st', r) ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold thread_serial_putc_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_putc_pmap_unchanged; eauto.
  Qed.

  Lemma thread_cons_buf_read_loop_pmap_unchanged : forall st st' len addr read vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    thread_cons_buf_read_loop_spec len addr st = Some (st', read) ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold thread_cons_buf_read_loop_spec; intros * Hspec; destruct_spec Hspec.
    eapply cons_buf_read_loop_pmap_unchanged; eauto.
  Qed.

  Lemma sys_getc_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    sys_getc_spec st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold sys_getc_spec; intros * Hspec; destruct_spec Hspec.
    edestruct thread_serial_intr_disable_pmap_unchanged as (-> & ->); eauto.
    edestruct thread_cons_buf_read_pmap_unchanged as (-> & ->); eauto.
    edestruct thread_serial_intr_enable_pmap_unchanged as (-> & ->); eauto.
    edestruct uctx_set_retval1_pmap_unchanged as (-> & ->); eauto.
    edestruct uctx_set_errno_pmap_unchanged as (-> & ->); eauto.
  Qed.

  Lemma sys_putc_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    sys_putc_spec st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold sys_putc_spec; intros * Hspec; destruct_spec Hspec.
    edestruct thread_serial_intr_disable_pmap_unchanged as (-> & ->); eauto.
    edestruct thread_serial_putc_pmap_unchanged as (-> & ->); eauto.
    edestruct thread_serial_intr_enable_pmap_unchanged as (-> & ->); eauto.
    edestruct uctx_set_retval1_pmap_unchanged as (-> & ->); eauto.
    edestruct uctx_set_errno_pmap_unchanged as (-> & ->); eauto.
  Qed.

  Lemma sys_getcs_pmap_unchanged : forall st st' vaddr,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    sys_getcs_spec st = Some st' ->
    get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st'
    /\ st.(pperm) = st'.(pperm).
  Proof.
    unfold sys_getcs_spec; intros * Hspec; destruct_spec Hspec.
    edestruct thread_serial_intr_disable_pmap_unchanged as (-> & ->); eauto.
    edestruct thread_cons_buf_read_loop_pmap_unchanged as (-> & ->); eauto.
    edestruct thread_serial_intr_enable_pmap_unchanged as (-> & ->); eauto.
    edestruct uctx_set_retval1_pmap_unchanged as (-> & ->); eauto.
    edestruct uctx_set_errno_pmap_unchanged as (-> & ->); eauto.
  Qed.

  (** No user-visible events are generated. *)
  Definition nil_trace_case t t' :=
    let new := trace_of_ostrace (strip_common_prefix IOEvent_eq t t') in
    t = common_prefix IOEvent_eq t t' /\
    new = trace_of_ostrace nil.

  (** At most one user-visible read event is generated. *)
  Definition getc_trace_case t t' ret :=
    let new := trace_of_ostrace (strip_common_prefix IOEvent_eq t t') in
    t = common_prefix IOEvent_eq t t' /\
    ((ret = -1 /\ new = trace_of_ostrace nil) \/
     (0 <= ret <= 255 /\ forall logIdx strIdx,
        new = trace_of_ostrace (IOEvGetc logIdx strIdx ret :: nil))).

  (** Amedeo, Oggi 02032021 *)
  Definition getcs_trace_case t t' ret char_lst :=
    let new := trace_of_ostrace (strip_common_prefix IOEvent_eq t t') in
    t = common_prefix IOEvent_eq t t' /\
    ((ret = Zlength char_lst /\ forall logIdx strIdx,
        new = trace_of_ostrace (map (fun c => IOEvGetc logIdx strIdx c) char_lst))).

  (** At most one user-visible write event is generated. *)
  Definition putc_trace_case t t' c ret :=
    let new := trace_of_ostrace (strip_common_prefix IOEvent_eq t t') in
    t = common_prefix IOEvent_eq t t' /\
    ((ret = -1 /\ new = trace_of_ostrace nil) \/
     (ret = c mod 256 /\ forall logIdx,
        new = trace_of_ostrace (IOEvPutc logIdx c :: nil))).

  Lemma trace_of_ostrace_app : forall otr otr',
    let tr := trace_of_ostrace otr in
    let tr' := trace_of_ostrace otr' in
    trace_of_ostrace (otr ++ otr') = app_trace tr tr'.
  Proof.
    induction otr as [| ev otr]; cbn; intros *; auto.
    destruct ev; cbn; auto.
    all: rewrite IHotr; auto.
  Qed.

  Lemma IOEvRecvs_not_visible : forall tr,
    (forall ev, In ev tr -> exists logIdx strIdx c, ev = IOEvRecv logIdx strIdx c) ->
    trace_of_ostrace tr = TEnd.
  Proof.
    induction tr; cbn; intros Htr; auto.
    edestruct Htr as (? & ? & ? & ?); auto; subst; cbn; auto.
  Qed.

  Lemma mkRecvEvents_not_visible : forall cs logIdx,
    trace_of_ostrace (mkRecvEvents logIdx cs) = TEnd.
  Proof.
    intros; apply IOEvRecvs_not_visible; intros * Hin.
    apply in_mkRecvEvents in Hin.
    destruct Hin as (? & ? & ? & ? & ?); eauto.
  Qed.

  Lemma nil_trace_getc_trace : forall t t',
    nil_trace_case t t' <-> getc_trace_case t t' (-1).
  Proof.
    unfold nil_trace_case, getc_trace_case; intuition (auto; easy).
  Qed.

  Lemma nil_trace_putc_trace : forall t t' c,
    nil_trace_case t t' <-> putc_trace_case t t' c (-1).
  Proof.
    unfold nil_trace_case, putc_trace_case; intuition auto.
    pose proof (Z.mod_pos_bound c 256 ltac:(lia)); lia.
  Qed.

  Lemma nil_trace_case_refl : forall st, nil_trace_case st st.
  Proof.
    red; intros; unfold strip_common_prefix.
    rewrite common_prefix_full, leb_correct, skipn_exact_length; cbn; auto.
  Qed.

  Local Hint Resolve nil_trace_case_refl.

  Corollary getc_trace_case_refl : forall st, getc_trace_case st st (-1).
  Proof. intros; rewrite <- nil_trace_getc_trace; auto. Qed.

  Corollary putc_trace_case_refl : forall st c, putc_trace_case st st c (-1).
  Proof. intros; rewrite <- nil_trace_putc_trace; auto. Qed.

  Local Hint Resolve getc_trace_case_refl.
  Local Hint Resolve putc_trace_case_refl.

  Lemma getc_trace_case_trans : forall t t' t'' r,
    nil_trace_case t t' ->
    getc_trace_case t' t'' r ->
    getc_trace_case t t'' r.
  Proof.
    intros * Htr Htr'; red.
    destruct Htr as (Heq & Htr), Htr' as (Heq' & Htr'); subst.
    apply common_prefix_correct in Heq; apply common_prefix_correct in Heq'.
    destruct Heq, Heq'; subst.
    unfold strip_common_prefix in *.
    rewrite !app_length, leb_correct in * by lia.
    rewrite <- app_assoc.
    rewrite common_prefix_app, skipn_app1, skipn_exact_length in *;
      rewrite ?app_length; auto; cbn in *.
    rewrite trace_of_ostrace_app.
    rewrite Htr; destruct Htr' as [(? & ->) | ?]; subst; auto.
  Qed.

  Lemma getc_trace_case_trans' : forall t t' t'' r,
    getc_trace_case t t' r ->
    nil_trace_case t' t'' ->
    getc_trace_case t t'' r.
  Proof.
    intros * Htr Htr'; red.
    destruct Htr as (Heq & Htr), Htr' as (Heq' & Htr'); subst.
    apply common_prefix_correct in Heq; apply common_prefix_correct in Heq'.
    destruct Heq, Heq'; subst.
    unfold strip_common_prefix in *.
    rewrite !app_length, leb_correct in * by lia.
    rewrite <- app_assoc.
    rewrite common_prefix_app, skipn_app1, skipn_exact_length in *;
      rewrite ?app_length; auto; cbn in *.
    rewrite trace_of_ostrace_app.
    rewrite Htr'; destruct Htr as [(? & ->) | (? & ->)]; subst; auto; constructor.
  Qed.

  Corollary nil_trace_case_trans : forall t t' t'',
    nil_trace_case t t' ->
    nil_trace_case t' t'' ->
    nil_trace_case t t''.
  Proof.
    intros * ?; rewrite !nil_trace_getc_trace; eauto using getc_trace_case_trans.
  Qed.

  Lemma putc_trace_case_trans : forall t t' t'' c r,
    nil_trace_case t t' ->
    putc_trace_case t' t'' c r ->
    putc_trace_case t t'' c r.
  Proof.
    intros * Htr Htr'; red.
    destruct Htr as (Heq & Htr), Htr' as (Heq' & Htr'); subst.
    apply common_prefix_correct in Heq; apply common_prefix_correct in Heq'.
    destruct Heq, Heq'; subst.
    unfold strip_common_prefix in *.
    rewrite !app_length, leb_correct in * by lia.
    rewrite <- app_assoc.
    rewrite common_prefix_app, skipn_app1, skipn_exact_length in *;
      rewrite ?app_length; auto; cbn in *.
    rewrite trace_of_ostrace_app.
    pose proof (Z.mod_pos_bound c 256 ltac:(lia)).
    rewrite Htr; destruct Htr' as [(? & ->) | ?]; subst; auto.
  Qed.

  Lemma putc_trace_case_trans' : forall t t' t'' c r,
    putc_trace_case t t' c r ->
    nil_trace_case t' t'' ->
    putc_trace_case t t'' c r.
  Proof.
    intros * Htr Htr'; red.
    destruct Htr as (Heq & Htr), Htr' as (Heq' & Htr'); subst.
    apply common_prefix_correct in Heq; apply common_prefix_correct in Heq'.
    destruct Heq, Heq'; subst.
    unfold strip_common_prefix in *.
    rewrite !app_length, leb_correct in * by lia.
    rewrite <- app_assoc.
    rewrite common_prefix_app, skipn_app1, skipn_exact_length in *;
      rewrite ?app_length; auto; cbn in *.
    rewrite trace_of_ostrace_app.
    pose proof (Z.mod_pos_bound c 256 ltac:(lia)).
    rewrite Htr'; destruct Htr as [(? & ->) | (? & ->)]; subst; auto.
  Qed.

  Lemma cons_intr_aux_trace_case : forall st st',
    cons_intr_aux st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    unfold cons_intr_aux, nil_trace_case; intros * Hspec; destruct_spec Hspec.
    - prename (Coqlib.zeq _ _ = _) into Htmp; clear Htmp.
      destruct st; cbn in *; subst; cbn in *.
      rewrite common_prefix_app, app_length, leb_correct by lia.
      rewrite skipn_app1, skipn_exact_length; cbn; auto using mkRecvEvents_not_visible.
    - prename (Coqlib.zeq _ _ = _) into Htmp; clear Htmp.
      destruct st; cbn in *; subst; cbn in *.
      rewrite common_prefix_app, app_length, leb_correct by lia.
      rewrite skipn_app1, skipn_exact_length; cbn; auto using mkRecvEvents_not_visible.
  Qed.

  Lemma serial_intr_enable_aux_trace_case : forall n st st',
    serial_intr_enable_aux n st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    induction n; intros * Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto.
    prename cons_intr_aux into Hspec'.
    eapply nil_trace_case_trans; [eapply cons_intr_aux_trace_case |]; eauto.
  Qed.

  Lemma serial_intr_enable_trace_case : forall st st',
    serial_intr_enable_spec st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    unfold serial_intr_enable_spec; intros * Hspec; destruct_spec Hspec.
    prename serial_intr_enable_aux into Hspec.
    eapply serial_intr_enable_aux_trace_case in Hspec.
    destruct st, r; auto.
  Qed.

  Lemma serial_intr_disable_aux_trace_case : forall n mask st st',
    serial_intr_disable_aux n mask st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    induction n; intros * Hspec; cbn -[cons_intr_aux] in Hspec; inj; auto.
    destruct_spec Hspec; auto.
    - eapply IHn in Hspec.
      destruct st, st'; cbn in *.
      prename serial_intr into Hspec'.
      unfold serial_intr in Hspec'; destruct_spec Hspec'.
      destruct o; [| rewrite app_nil_r in Hspec; auto].
      destruct Hspec as (Heq & Htr).
      apply common_prefix_correct in Heq.
      destruct Heq; subst; red.
      rewrite <- Htr; unfold strip_common_prefix.
      rewrite common_prefix_app, <- app_assoc, common_prefix_app.
      rewrite !app_length, !leb_correct by (cbn; lia).
      rewrite skipn_app1, skipn_exact_length; auto.
      rewrite (app_assoc io_log), <- app_length.
      rewrite skipn_app1, skipn_exact_length; cbn; auto.
    - prename cons_intr_aux into Hspec'.
      eapply cons_intr_aux_trace_case in Hspec'.
      eapply IHn in Hspec.
      eapply nil_trace_case_trans; [| eapply Hspec]; eauto.
      destruct st, r, st'; cbn in *.
      prename serial_intr into Hspec''.
      unfold serial_intr in Hspec''; destruct_spec Hspec''.
      destruct o; [| rewrite app_nil_r in Hspec'; auto].
      destruct Hspec' as (Heq & Htr).
      apply common_prefix_correct in Heq.
      destruct Heq; subst; red.
      rewrite <- Htr; unfold strip_common_prefix.
      rewrite common_prefix_app, <- app_assoc, common_prefix_app.
      rewrite !app_length, !leb_correct by (cbn; lia).
      rewrite skipn_app1, skipn_exact_length; auto.
      rewrite (app_assoc io_log), <- app_length.
      rewrite skipn_app1, skipn_exact_length; cbn; auto.
  Qed.

  Lemma serial_intr_disable_trace_case : forall st st',
    serial_intr_disable_spec st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    unfold serial_intr_disable_spec; intros * Hspec; destruct_spec Hspec.
    prename serial_intr_disable_aux into Hspec.
    eapply serial_intr_disable_aux_trace_case in Hspec.
    destruct st, r; auto.
  Qed.

  Lemma thread_serial_intr_enable_trace_case : forall st st',
    thread_serial_intr_enable_spec st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    unfold thread_serial_intr_enable_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_intr_enable_trace_case; eauto.
  Qed.

(* amedeo, read this *)
  Lemma thread_serial_intr_disable_trace_case : forall st st',
    thread_serial_intr_disable_spec st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    unfold thread_serial_intr_disable_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_intr_disable_trace_case; eauto.
  Qed.

  Lemma uctx_set_retval1_trace_case : forall st v st',
    uctx_set_retval1_spec v st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    unfold uctx_set_retval1_spec; intros * Hspec; destruct_spec Hspec.
    destruct st; auto.
  Qed.

  Lemma uctx_set_errno_trace_case : forall st e st',
    uctx_set_errno_spec e st = Some st' ->
    nil_trace_case st.(io_log) st'.(io_log).
  Proof.
    unfold uctx_set_errno_spec; intros * Hspec; destruct_spec Hspec.
    destruct st; auto.
  Qed.

  Lemma serial_putc_putc_trace_case : forall st c st' r,
    serial_putc_spec c st = Some (st', r) ->
    putc_trace_case st.(io_log) st'.(io_log) c r.
  Proof.
    unfold serial_putc_spec; intros * Hspec; destruct_spec Hspec; eauto.
    - prename (Coqlib.zeq _ _ = _) into Htmp; clear Htmp.
      destruct st; cbn in *; subst; red.
      unfold strip_common_prefix.
      rewrite !app_length, leb_correct by lia.
      rewrite common_prefix_app, skipn_app1, skipn_exact_length; auto.
    - prename (Coqlib.zeq _ _ = _) into Htmp; clear Htmp.
      destruct st; cbn in *; subst; red.
      unfold strip_common_prefix.
      rewrite !app_length, leb_correct by lia.
      rewrite common_prefix_app, skipn_app1, skipn_exact_length; auto.
  Qed.

  Lemma cons_buf_read_trace_case : forall st st' c,
    valid_trace st ->
    cons_buf_read_spec st = Some (st', c) ->
    getc_trace_case st.(io_log) st'.(io_log) c /\ -1 <= c <= 255.
  Proof.
    unfold cons_buf_read_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    { split; eauto; lia. }
    prename (cons_buf _ = _) into Hcons.
    destruct st; cbn in *; unfold getc_trace_case.
    unfold strip_common_prefix.
    rewrite common_prefix_app, app_length, leb_correct by lia.
    rewrite skipn_app1, skipn_exact_length; cbn; auto.
    inv Hvalid; cbn in *.
    rewrite vt_trace_console0 in Hcons.
    assert (Hin: In (c, z0, n) (compute_console io_log)) by (rewrite Hcons; cbn; auto).
    apply in_console_in_trace in Hin.
    apply in_split in Hin; destruct Hin as (? & ? & ?); subst.
    edestruct vt_trace_serial0 as (_ & Henv); eauto.
    destruct (SerialEnv z0) eqn:Hrange; try easy.
    apply SerialRecv_in_range in Hrange.
    rewrite Forall_forall in Hrange.
    apply nth_error_In in Henv.
    apply Hrange in Henv.
    split; auto; lia.
  Qed.

  (* Wrong proof - useless 
  Theorem l_eq_l_plus_nil : forall (X:Type), forall (l:list X),
    (* l ++ nil = l. *)
    l = l ++ nil.
  Proof.
    intros.
    induction l as [| h t IH].
    - trivial.
    - rewrite IH. intuition.
  Qed. *)

  Theorem sum_l1_l2_nil_if_l2_eq_nil : forall (X:Type), forall (l1:list X), forall (l2:list X),
      l1 ++ l2 = l1 -> l2 = nil.
  Proof.
    intros.
    induction l1 as [| h t IH].
    - trivial.
    - inversion H0. simpl. rewrite IH. trivial. apply H2.
  Qed.

  Lemma strip_common_prefix_empty : forall {A} (Aeq : forall x y : A, {x = y} + {x <> y}) (xs : list A),
    strip_common_prefix Aeq xs xs = nil.
  Proof.
    intros.
    pose proof strip_common_prefix_correct Aeq xs xs.
    assert (length xs <= length xs)%nat.
    trivial.
    (*lapply H0.*)
    specialize (H0 H1).
    rewrite common_prefix_full in H0.
    simpl in H0.
    apply (sum_l1_l2_nil_if_l2_eq_nil A xs (strip_common_prefix Aeq xs xs)).
    symmetry. trivial.
    (* Locate "++". *)
    (* Search (?a ++ ?b = ?a). proven in software foundations *)
  Qed.

(* cons_buf_read_loop_spec (n : nat) (read : nat) (addr : Z) (abd : RData) : option (RData * Z) := *)
(*thread_cons_buf_read_loop_spec len buf_paddr d1 with*)
(* 09032021 *)
  Lemma cons_buf_read_loop_trace_case : forall st st' read addr ret n,
    valid_trace st ->
    cons_buf_read_loop_spec n read addr st = Some (st', ret) ->
    exists char_lst,
    getcs_trace_case st.(io_log) st'.(io_log) ret char_lst.
  Proof.
  (* unfold cons_buf_read_loop_spec. *)
  (* unfold getcs_trace_case. *)
  intros.
  revert dependent read. (* keeps universal quantification on everything that we reverted before the induction, then we do intros again for each case *)
  revert dependent addr.
  revert dependent st.
  induction n as [ | k Ih ].
  -  intros.
    simpl in H1. inversion H1. (* intervesion: whenever I have equality between two structures, takes out the pieces that must be equal *)
    exists nil.
    unfold getcs_trace_case.
    split. {
    rewrite common_prefix_full. trivial.
    }
    split. {
    admit.
    }
    {
    simpl. rewrite strip_common_prefix_empty. trivial.
    }
  - intros. simpl in H1. destruct_spec H1. apply cons_buf_read_trace_case in Heqo.
    {
     exists nil. unfold getcs_trace_case.
     split. {
    rewrite common_prefix_full. trivial.
    }
    split. {
    admit.
    }
    {
    simpl. rewrite strip_common_prefix_empty. trivial.
    }
    }
    {
      apply H0.
    }
    {
     pose proof cons_buf_read_trace_case st r z H0 Heqo. destruct H2.
     apply Ih in H1.
     destruct H1.
     exists (z :: x).
      unfold update_HP in H1. destruct r. simpl in *.
      unfold getcs_trace_case. unfold getcs_trace_case in H1. destruct H1 as [Hcommon [Hret Hevent]].
      unfold getc_trace_case in H2. destruct H2 as [Hcommonst].
      split.
      (* rewrite Hcommonst, Hcommon into 1/3 then break H1 into cases, z=-1 is wrong, rest is fine *)
      * 
    }

    (* 09032021 induction where induction hyp is too specific, read "Varying the Induction Hypothesis" at https://softwarefoundations.cis.upenn.edu/lf-current/Tactics.html *)

  (* induction on n, use cons_buf_read_trace_case in the inductive case, base case? *)
  Qed.

  Lemma thread_serial_putc_trace_case : forall st c st' r,
    thread_serial_putc_spec c st = Some (st', r) ->
    putc_trace_case st.(io_log) st'.(io_log) c r.
  Proof.
    unfold thread_serial_putc_spec; intros * Hspec; destruct_spec Hspec.
    eapply serial_putc_putc_trace_case; eauto.
  Qed.

  (* similar trace case: amedeo *)
  Lemma thread_cons_buf_read_trace_case : forall st st' c,
    valid_trace st ->
    thread_cons_buf_read_spec st = Some (st', c) ->
    getc_trace_case st.(io_log) st'.(io_log) c /\ -1 <= c <= 255.
  Proof.
    unfold thread_cons_buf_read_spec; intros * Hvalid Hspec; destruct_spec Hspec.
    eapply cons_buf_read_trace_case; eauto.
  Qed.

  (* Oggi 02032021 - Amedeo  *)
  Lemma thread_cons_buf_read_loop_trace_case : forall st st' len addr ret,
  valid_trace st ->
  thread_cons_buf_read_loop_spec len addr st = Some(st', ret) ->
    exists char_lst,
    getcs_trace_case st.(io_log) st'.(io_log) ret char_lst.
  Proof.
    unfold thread_cons_buf_read_loop_spec; intros * Hvalid Hspec. destruct_spec Hspec.
    eapply cons_buf_read_trace_case; eauto.
  Qed. 

  Lemma sys_getc_trace_case : forall st st' ret,
    valid_trace st ->
    sys_getc_spec st = Some st' ->
    get_sys_ret st' = Vint ret ->
    getc_trace_case st.(io_log) st'.(io_log) (Int.signed ret).
  Proof.
    unfold sys_getc_spec, get_sys_ret; intros * Hvalid Hspec Hret; destruct_spec Hspec.
    prename thread_serial_intr_disable_spec into Hspec1.
    prename thread_cons_buf_read_spec into Hspec2.
    prename thread_serial_intr_enable_spec into Hspec3.
    prename uctx_set_retval1_spec into Hspec4.
    assert (valid_trace r) by eauto using thread_serial_intr_disable_preserve_valid_trace.
    assert (valid_trace r0) by eauto using thread_cons_buf_read_preserve_valid_trace.
    assert (valid_trace r1) by eauto using thread_serial_intr_enable_preserve_valid_trace.
    assert (valid_trace r2) by eauto using uctx_set_retval1_preserve_valid_trace.
    assert (valid_trace st') by eauto using uctx_set_errno_preserve_valid_trace.
    eapply thread_serial_intr_disable_trace_case in Hspec1 as Htr.
    eapply thread_cons_buf_read_trace_case in Hspec2 as (Htr1 & Hrange); auto.
    eapply thread_serial_intr_enable_trace_case in Hspec3 as Htr2.
    eapply uctx_set_retval1_trace_case in Hspec4 as Htr3.
    eapply uctx_set_errno_trace_case in Hspec as Htr4.
    eapply getc_trace_case_trans'; [| eapply Htr4].
    eapply getc_trace_case_trans'; [| eapply Htr3].
    eapply getc_trace_case_trans'; [| eapply Htr2].
    eapply getc_trace_case_trans; [eapply Htr |]; eauto.
    enough (z = Int.signed ret); subst; auto.
    clear -Hspec Hspec4 Hret Htr1 Hrange.
    unfold uctx_set_retval1_spec in Hspec4; destruct_spec Hspec4.
    unfold uctx_set_errno_spec in Hspec; destruct_spec Hspec.
    destruct r1; cbn in *; subst.
    repeat (rewrite ZMap.gss in Hret || rewrite ZMap.gso in Hret by easy); inj.
    rewrite Int.signed_repr; auto; cbn; lia.
  Qed.

  Lemma sys_putc_trace_case : forall st st' c ret,
    sys_putc_spec st = Some st' ->
    get_sys_arg1 st = Vint c ->
    get_sys_ret st' = Vint ret ->
    putc_trace_case st.(io_log) st'.(io_log) (Int.unsigned c) (Int.signed ret).
  Proof.
    unfold sys_putc_spec, get_sys_arg1, get_sys_ret; intros * Hspec Harg Hret; destruct_spec Hspec.
    prename thread_serial_intr_disable_spec into Hspec1.
    prename thread_serial_putc_spec into Hspec2.
    prename thread_serial_intr_enable_spec into Hspec3.
    prename uctx_set_retval1_spec into Hspec4.
    prename uctx_arg2_spec into Hspec5.
    eapply thread_serial_intr_disable_trace_case in Hspec1 as Htr.
    eapply thread_serial_putc_trace_case in Hspec2 as (Htr1 & Hrange); auto.
    eapply thread_serial_intr_enable_trace_case in Hspec3 as Htr2.
    eapply uctx_set_retval1_trace_case in Hspec4 as Htr3.
    eapply uctx_set_errno_trace_case in Hspec as Htr4.
    eapply putc_trace_case_trans'; [| eapply Htr4].
    eapply putc_trace_case_trans'; [| eapply Htr3].
    eapply putc_trace_case_trans'; [| eapply Htr2].
    eapply putc_trace_case_trans; [eapply Htr |]; eauto.
    enough (z0 = Int.signed ret /\ z = Int.unsigned c) as (? & ?); subst; [split; auto |].
    clear -Hspec Hspec4 Hspec5 Harg Hret Htr1 Hrange.
    unfold uctx_set_retval1_spec in Hspec4; destruct_spec Hspec4.
    unfold uctx_set_errno_spec in Hspec; destruct_spec Hspec.
    unfold uctx_arg2_spec in Hspec5; destruct_spec Hspec5.
    destruct r1; cbn in *; subst.
    repeat (rewrite ZMap.gss in Hret || rewrite ZMap.gso in Hret by easy); inj.
    rewrite Int.signed_repr; auto; cbn; try lia.
    pose proof (Z.mod_pos_bound (Int.unsigned c) 256 ltac:(lia)).
    destruct Hrange as [(? & ?) | (? & ?)]; lia.
  Qed.

End Invariants.

Section SpecsCorrect.
  Import Mem.

  Context `{ThreadsConfigurationOps}.

  Notation toPaddr vaddr st :=
    (let curid := ZMap.get st.(CPU_ID) st.(cid) in
     match get_kernel_pa_spec curid vaddr st with
     | None => 0 | Some pa => pa end).

  Definition user_trace (ot ot' : ostrace) : trace :=
    trace_of_ostrace (strip_common_prefix IOEvent_eq ot ot').

  Definition trace_itree_match (z0 z : IO_itree) (ot ot' : ostrace) :=
    (* Compute the OS-generated trace of newly added events *)
    let ot_new := strip_common_prefix IOEvent_eq ot ot' in
    (* Filter out the user-invisible events *)
    let t := trace_of_ostrace ot_new in
    (* The new itree 'consumed' the OS-generated trace *)
    consume_trace z0 z t.

  Record block_to_addr := {
    b2a_map : block -> Z;
    b2a_disjoint : forall m b1 b2 ofs1 ofs2,
      b1 <> b2 ->
      perm m b1 ofs1 Cur Nonempty ->
      perm m b2 ofs2 Cur Nonempty ->
      b2a_map b1 + ofs1 <> b2a_map b2 + ofs2;
  }.
  Variable b2a : block_to_addr.

  Lemma block_to_addr_range_perm_disjoint : forall len m b1 b2 ofs1 ofs2,
    let addr1 := b2a.(b2a_map) b1 + ofs1 in
    let addr2 := b2a.(b2a_map) b2 + ofs2 in
    b1 <> b2 ->
    perm m b1 ofs1 Cur Nonempty ->
    range_perm m b2 ofs2 (ofs2 + Z.of_nat len) Cur Nonempty ->
    addr1 < addr2 \/ addr2 + Z.of_nat len <= addr1.
  Proof.
    induction len; cbn -[Z.of_nat]; intros * Hblock Hperm1 Hperm2; hnf in Hperm2; [lia |].
    edestruct IHlen; eauto.
    { hnf; intros; apply Hperm2; lia. }
    right.
    eapply (b2a.(b2a_disjoint) m b1 b2 ofs1 (ofs2 + Z.of_nat len)) in Hperm1; eauto; try lia.
    eapply Hperm2; lia.
  Qed.

  Definition R_mem (m : mem) (st : RData) : Prop :=
    forall b ofs paddr,
      let vaddr := b2a.(b2a_map) b + ofs in
      let curid := ZMap.get st.(CPU_ID) st.(cid) in
      Some paddr = get_kernel_pa_spec curid vaddr st ->
      ZMap.get (paddr / PAGE_SIZE) st.(pperm) = PGAlloc ->
      perm m b ofs Cur Nonempty ->
      match ZMap.get ofs (m.(mem_contents) !! b) with
      | Fragment _ _ _ => True
      | v => v = FlatMem.FlatMem2MemVal (ZMap.get paddr st.(HP))
      end.

  Definition mem_to_flatmem (f : flatmem) (m : mem) (b : block) (ofs len : Z) : flatmem :=
    let contents := getN (Z.to_nat len) ofs (m.(mem_contents) !! b) in
    let addr := b2a.(b2a_map) b + ofs in
    FlatMem.setN contents addr f.

  Program Definition flatmem_to_mem (st : RData) (m : mem) (b : block) (ofs len : Z) : mem :=
    let (cont, acc, nxt, amax, nxt_no, _) := m in
    let addr := toPaddr (b2a.(b2a_map) b + ofs) st in
    let bytes := FlatMem.getN (Z.to_nat len) addr st.(HP) in
    let contents := setN bytes ofs (cont !! b) in
    mkmem (PMap.set b contents cont) acc nxt amax nxt_no _.
  Next Obligation.
    cbn; intros; destruct (Pos.eq_dec b b0) eqn:?; subst.
    - rewrite PMap.gss, setN_default; auto.
    - rewrite PMap.gso; auto.
  Defined.

  Local Transparent storebytes.
  Theorem range_perm_storebytes_less : forall m1 b ofs bytes len,
    Zlength bytes <= len ->
    range_perm m1 b ofs (ofs + len) Cur Writable ->
    { m2 : mem | storebytes m1 b ofs bytes = Some m2 }.
  Proof.
    unfold storebytes; intros * Hlen Hperm.
    destruct range_perm_dec as [? | Hperm']; eauto.
    exfalso; eapply Hperm'.
    rewrite <- Zlength_correct.
    red; intros; apply Hperm; lia.
  Defined.
  Local Opaque storebytes.

  Lemma flatmem_to_mem_contents : forall st m b ofs len,
    let addr := toPaddr (b2a.(b2a_map) b + ofs) st in
    let bytes := FlatMem.getN (Z.to_nat len) addr st.(HP) in
    let contents := setN bytes ofs (m.(mem_contents) !! b) in
    mem_contents (flatmem_to_mem st m b ofs len) = PMap.set b contents m.(mem_contents).
  Proof.
    unfold flatmem_to_mem; intros *; destruct m; cbn.
    destruct (get_kernel_pa_spec _ _); auto.
  Qed.

  Lemma flatmem_to_mem_perm : forall st m b ofs len b' ofs' k p,
    perm (flatmem_to_mem st m b ofs len) b' ofs' k p <-> perm m b' ofs' k p.
  Proof.
    unfold perm, flatmem_to_mem; intros *; destruct m; cbn; easy.
  Qed.

  Lemma flatmem_to_mem_nextblock : forall st m b ofs len,
    nextblock (flatmem_to_mem st m b ofs len) = nextblock m.
  Proof.
    unfold flatmem_to_mem; intros *; destruct m; cbn; auto.
  Qed.

  Import mem_lessdef.
  Lemma flatmem_to_mem_storebytes_equiv : forall st m b ofs vs m',
    let addr := toPaddr (b2a.(b2a_map) b + ofs) st in
    storebytes m b ofs (inj_bytes vs) = Some m' ->
    let st' := st {HP: FlatMem.storebytes st.(HP) addr (inj_bytes vs)} in
    mem_equiv (flatmem_to_mem st' m b ofs (Zlength vs)) m'.
  Proof.
    intros * Hm'; subst addr; apply mem_lessdef_equiv; repeat split.
    - intros * Hload.
      edestruct loadbytes_inj as (? & Hload' & ?); eauto.
      3: rewrite Z.add_0_r in Hload'; eauto.
      2: auto.
      unfold inject_id; constructor; intros * ?; inj.
      + rewrite Z.add_0_r, flatmem_to_mem_perm; eauto using perm_storebytes_1.
      + exists 0; auto.
      + intros Hperm; rewrite Z.add_0_r.
        apply storebytes_mem_contents in Hm' as ->.
        unfold FlatMem.storebytes.
        rewrite flatmem_to_mem_contents, ZtoNat_Zlength, <- length_inj_bytes.
        destruct st; cbn; rewrite FlatMem.getN_setN.
        apply mem_lemmas.memval_inject_id_refl.
    - intros * Hperm.
      rewrite flatmem_to_mem_perm in Hperm.
      eapply perm_storebytes_1; eauto.
    - erewrite flatmem_to_mem_nextblock, <- nextblock_storebytes; eauto; lia.
    - intros * Hload.
      edestruct loadbytes_inj as (? & Hload' & ?); eauto.
      3: rewrite Z.add_0_r in Hload'; eauto.
      2: auto.
      unfold inject_id; constructor; intros * ?; inj.
      + rewrite Z.add_0_r, flatmem_to_mem_perm; eauto using perm_storebytes_2.
      + exists 0; auto.
      + intros Hperm; rewrite Z.add_0_r.
        apply storebytes_mem_contents in Hm' as ->.
        unfold FlatMem.storebytes.
        rewrite flatmem_to_mem_contents, ZtoNat_Zlength, <- length_inj_bytes.
        destruct st; cbn; rewrite FlatMem.getN_setN.
        apply mem_lemmas.memval_inject_id_refl.
    - intros * Hperm.
      rewrite flatmem_to_mem_perm.
      eapply perm_storebytes_2 in Hperm; eauto.
    - erewrite flatmem_to_mem_nextblock, nextblock_storebytes; eauto; lia.
  Qed.

  Lemma setN_inside : forall vs p q c,
    p <= q < p + Z.of_nat (length vs) ->
    ZMap.get q (setN vs p c) = nth (Z.to_nat (q - p)) vs Undef.
  Proof.
    clear.
    induction vs; cbn -[Z.of_nat]; intros * Hrange; [lia |].
    assert (p = q \/ p < q) as [? | ?] by lia; subst.
    { rewrite Z.sub_diag, setN_outside, ZMap.gss; auto; lia. }
    rewrite IHvs; auto; try lia.
    replace (q - (p + 1)) with (q - p - 1) by lia.
    destruct (Z.to_nat (q - p)) eqn:Hsub.
    { apply (f_equal Z.of_nat) in Hsub.
      rewrite Z2Nat.id in Hsub; lia.
    }
    apply (f_equal Z.of_nat) in Hsub.
    rewrite Z2Nat.id in Hsub; try lia.
    rewrite Hsub, Z2Nat.inj_sub, Nat2Z.id; try lia.
    cbn; rewrite Nat.sub_0_r; auto.
  Qed.

  Record R_sys_getc_correct k z m st st' ret := {
    (* New itree is old k applied to result, or same as old itree if nothing
       to read *)
    getc_z' := if 0 <=? Int.signed ret then k (Byte.repr (Int.signed ret)) else z;

    (* Post condition holds on new state, itree, and result *)
    getc_post_ok : getchar_post' m m ret (k, z) getc_z';
    (* The itrees and OS traces agree on the external events *)
    getc_itree_trace_ok : trace_itree_match z getc_z' st.(io_log) st'.(io_log);
    (* The new trace is valid *)
    getc_trace_ok : valid_trace st';
    (* The memory is unchanged *)
    getc_mem_ok : R_mem m st';
  }.

  (*m is the user memory, 
  k,z have to do with ITree (?) *)
  Lemma sys_getc_correct k z m st st' :
    (* Initial trace is valid *)
    valid_trace st ->
    R_mem m st (*R_mem says that the user memory m corresponds to the virtual memory*) ->
    (* Pre condition holds *)
    getchar_pre' m k z ->
    (* sys_getc returns some state *)
    sys_getc_spec st = Some st' ->
    exists ret,
(* = is logical equal - they are the same - always in Coq *)
      get_sys_ret st' = Vint ret (*memory value of ret must be of an integer type*) /\ (*and representation in Coq*)
      R_sys_getc_correct k z m st st' ret.
  Proof.
  (* START ANALYSIS sys_getc_spec succeeded: anytime I write sys_getc_spec st = Some st' I prove it like this *)
    unfold getchar_pre', get_sys_ret; intros Hvalid HRmem Hpre Hspec.
    pose proof Hspec. (*duplicate hypothesis*)
    apply sys_getc_preserve_valid_trace in Hspec as Hvalid'; auto.
    apply sys_getc_mem_unchanged in Hspec as Hmem.
    pose proof Hspec as Htrace_case.
    unfold sys_getc_spec in Hspec; destruct_spec Hspec.
    (*z0 : Z
      Heqo0 : thread_cons_buf_read_spec r = Some (r0, z0)
      This is the x in the sys_getc_spec *)
    prename (thread_cons_buf_read_spec) into Hread.
    apply thread_cons_buf_read_trace_case in Hread as (_ & ?). (*read the conclusions and throw the first piece away and select the second piece*)
    2: eapply (thread_serial_intr_disable_preserve_valid_trace st); eauto.
    unfold uctx_set_errno_spec in Hspec; destruct_spec Hspec.
    prename (uctx_set_retval1_spec) into Hspec.
    unfold uctx_set_retval1_spec in Hspec; destruct_spec Hspec.
    destruct r1; cbn in *.
    repeat (rewrite ZMap.gss in * || rewrite ZMap.gso in * by easy); subst; inj.
    do 2 esplit; eauto.
    eapply sys_getc_trace_case in Htrace_case; eauto.
    (* sys_getc_spec ANALYSIS END! *)
    2: unfold get_sys_ret; cbn; repeat (rewrite ZMap.gss || rewrite ZMap.gso by easy); auto.
    constructor; eauto; hnf.
    - (* getchar_post *)
      split; auto; cbn in *.
      rewrite Int.signed_repr by (cbn; lia).
      destruct (Coqlib.zeq z0 (-1)); subst; auto.
      left; split; try lia.
      rewrite Zle_imp_le_bool by lia; auto.
    - (* trace_itree_match *)
      rewrite Int.signed_repr in * by (cbn; lia).
      cbn in *; destruct Htrace_case as (Htr & Hcase).
      intros * Htrace; cbn.
      destruct Hcase as [(? & ->) | (? & Heq)]; subst; auto.
      rewrite Zle_imp_le_bool in Htrace by lia.
      unshelve erewrite Heq; try solve [constructor].
      apply Hpre.
      hnf; cbn; repeat constructor; auto.
    - (* R_mem *)
      intros; edestruct sys_getc_pmap_unchanged as (Hpa & Hperm); eauto.
      apply HRmem; rewrite ?Hpa, ?Hperm; auto.
  Qed.

  Record R_sys_putc_correct c k z m st st' ret := {
    (* New itree is old k, or same as old itree if send failed *)
    putc_z' := if 0 <=? Int.signed ret then k else z;

    (* Post condition holds on new state, itree, and result *)
    putc_post_ok : putchar_post m m ret (c, k) putc_z';
    (* The itrees and OS traces agree on the external events *)
    putc_itree_trace_ok : trace_itree_match z putc_z' st.(io_log) st'.(io_log);
    (* The new trace is valid *)
    putc_trace_ok : valid_trace st';
    (* The memory is unchanged *)
    putc_mem_ok : R_mem m st';
  }.

  Lemma sys_putc_correct c k z m st st' :
    (* Initial trace is valid *)
    valid_trace st ->
    R_mem m st ->
    (* Pre condition holds *)
    putchar_pre m (c, k) z ->
    (* c is passed as an argument *)
    get_sys_arg1 st = functional_base.Vubyte c ->
    (* sys_putc returns some state *)
    sys_putc_spec st = Some st' ->
    exists ret,
      get_sys_ret st' = Vint ret /\
      R_sys_putc_correct c k z m st st' ret.
  Proof.
    unfold putchar_pre, get_sys_arg1, get_sys_ret; intros Hvalid HRmem Hpre Harg Hspec.
    pose proof Hspec.
    apply sys_putc_mem_unchanged in Hspec as Hmem.
    pose proof (sys_putc_preserve_valid_trace _ _ Hvalid Hspec).
    pose proof Hspec as Htrace_case.
    unfold sys_putc_spec in Hspec; destruct_spec Hspec.
    prename (thread_serial_putc_spec) into Hput.
    apply thread_serial_putc_trace_case in Hput.
    assert (-1 <= z1 <= 255).
    { pose proof (Z.mod_pos_bound z0 256 ltac:(lia)).
      destruct Hput as (? & [(? & ?) | (? & ?)]); subst; lia.
    }
    unfold uctx_set_errno_spec in Hspec; destruct_spec Hspec.
    prename (uctx_set_retval1_spec) into Hspec.
    unfold uctx_set_retval1_spec in Hspec; destruct_spec Hspec.
    prename (uctx_arg2_spec) into Hspec.
    unfold uctx_arg2_spec in Hspec; destruct_spec Hspec.
    destruct r1; cbn in *.
    repeat (rewrite ZMap.gss in * || rewrite ZMap.gso in * by easy); subst; inj.
    do 2 esplit; eauto.
    eapply sys_putc_trace_case in Htrace_case; eauto.
    2: unfold get_sys_ret; cbn; repeat (rewrite ZMap.gss || rewrite ZMap.gso by easy); auto.
    pose proof (Byte.unsigned_range_2 c).
    rewrite Int.unsigned_repr in * by functional_base.rep_omega.
    constructor; eauto; hnf.
    - (* putchar_post *)
      split; auto; cbn in *.
      rewrite Int.signed_repr by (cbn; lia).
      destruct (Coqlib.zeq z1 (-1)); subst; auto.
      destruct (eq_dec.eq_dec _ _); try easy.
      rewrite Zle_imp_le_bool by lia.
      destruct Hput as (? & [(? & ?) | (? & ?)]); subst; auto; try lia.
      rewrite Zmod_small; auto; functional_base.rep_omega.
    - (* trace_itree_match *)
      rewrite Int.signed_repr in * by (cbn; lia).
      cbn in *; destruct Htrace_case as (Htr & Hcase).
      intros * Htrace; cbn.
      destruct Hcase as [(? & ->) | (? & Heq)]; subst; auto.
      pose proof (Z.mod_pos_bound (Byte.unsigned c) 256 ltac:(lia)).
      rewrite Zle_imp_le_bool in Htrace by lia.
      unshelve erewrite Heq; try solve [constructor].
      eapply Traces.sutt_trace_incl; eauto; cbn.
      rewrite Byte.repr_unsigned.
      hnf; cbn; repeat constructor; auto.
    - (* R_mem *)
      intros; edestruct sys_putc_pmap_unchanged as (Hpa & Hperm); eauto.
      apply HRmem; rewrite ?Hpa, ?Hperm; auto.
  Qed.

  (* TODO: temporary *)
  Section Post.
  Import VST.msl.shares.
  Import VST.veric.mem_lessdef.
  Context {E : Type -> Type} {IO_E : @IO_event nat -< E}.
  Definition getchars_post (m0 m : mem) r (witness : share * val * Z * (list byte -> IO_itree)) (z : @IO_itree E) :=
    let '(sh, buf, len, k) := witness in Int.unsigned r <= len /\
      exists msg, Zlength msg = Int.unsigned r /\ z = k msg /\
      match buf with Vptr b ofs => exists m', Mem.storebytes m0 b (Ptrofs.unsigned ofs) (bytes_to_memvals msg) = Some m' /\
          mem_equiv m m'
      | _ => False end.
  End Post.

  Record R_sys_getcs_correct sh buf ofs len k z m m' st st' ret msg := {
    getcs_z' := k msg;

    (* Post condition holds on new state, itree, and result *)
    getcs_post_ok : getchars_post m m' ret (sh, (Vptr buf ofs), len, k) getcs_z';
    (* The itrees and OS traces agree on the external events *)
    getcs_itree_trace_ok : trace_itree_match z getcs_z' st.(io_log) st'.(io_log);
    (* The new trace is valid *)
    getcs_trace_ok : valid_trace st';
    (* The memory has changed *)
    getcs_mem_ok : R_mem m' st';
  }.

   (* Choose a syscall and then tell Mansky, so we can see if we have a CertikOS spec for it already. *)

   (* 25/01/2021 example of how we read a return value from physical memory *)
  Lemma sys_getcs_correct sh buf ofs len k z m st st' :
    let curid := ZMap.get st.(CPU_ID) st.(cid) in
    let addr := b2a.(b2a_map) buf + Ptrofs.unsigned ofs in
    0 <= addr <= Int.max_unsigned ->
    0 <= len <= Int.max_unsigned ->
    (* Initial trace is valid *)
    valid_trace st ->
    R_mem m st ->
    (* Pre condition holds *)
    getchars_pre m (sh, Vptr buf ofs, len, k) z ->
    (* addr and len are passed as arguments *)
    get_sys_arg1 st = Vint (Int.repr addr) ->
    get_sys_arg2 st = Vint (Int.repr len) ->
    (* sys_getcs returns some state *)
    sys_getcs_spec st = Some st' ->
    exists ret msg paddr m',
      Some paddr = get_kernel_pa_spec curid addr st /\
      get_sys_ret st' = Vint ret /\ (* ret is the number of bytes returned *)
      inj_bytes msg = FlatMem.loadbytes st'.(HP) paddr (Int.unsigned ret) /\ (*st'.(HP) physical memory in state st*)
      (* the return message msg is stored in physical memory at paddr *)
      R_sys_getcs_correct sh buf ofs len k z m m' st st' ret msg.
  Proof.
    unfold getchars_pre, get_sys_ret; intros ? ? Hvalid HRmem Hpre Harg1 Harg2 Hspec.
    pose proof Hspec.
    apply sys_getcs_preserve_valid_trace in Hspec as Hvalid'; auto.
    (* pose proof Hspec as Htrace_case. *)
    unfold sys_getcs_spec in Hspec; destruct_spec Hspec.
SearchAbout r.
    prename (thread_cons_buf_read_loop_spec) into Hread.
    pose proof Hread as Hread2. (* amedeo: we duplicate Hread into Hread2 for checking the itree match case *)
    apply thread_cons_buf_read_loop_mem_changed in Hread as (msg & Hlen & ? & Hmem).
SearchAbout r.
    (* apply thread_cons_buf_read_getcs_trace_case in Hread as (_ & ?). *)
    (* 2: eapply (thread_serial_intr_disable_preserve_valid_trace st); eauto. *)
    unfold uctx_set_errno_spec in Hspec; destruct_spec Hspec.
    prename (uctx_set_retval1_spec) into Hspec.
    unfold uctx_set_retval1_spec in Hspec; destruct_spec Hspec.
    prename (uctx_arg2_spec) into Hspec.
    unfold uctx_arg2_spec in Hspec; destruct_spec Hspec.
    prename (uctx_arg3_spec) into Hspec.
    unfold uctx_arg3_spec in Hspec; destruct_spec Hspec.
    prename thread_serial_intr_enable_spec into Henable.
    apply thread_serial_intr_enable_mem_unchanged in Henable as Hmem'.
    prename thread_serial_intr_disable_spec into Hdisable.
    apply thread_serial_intr_disable_mem_unchanged in Hdisable as Hmem''.
    rewrite Hmem', <- Hmem'' in Hmem.
    destruct r1; cbn in *.
    repeat (rewrite ZMap.gss in * || rewrite ZMap.gso in * by easy); subst; inj.
    (* eapply sys_putc_trace_case in Htrace_case; eauto. *)
    (* 2: unfold get_sys_ret; cbn; repeat (rewrite ZMap.gss || rewrite ZMap.gso by easy); auto. *)
    assert (Haddr: Int.unsigned i = b2a.(b2a_map) buf + Ptrofs.unsigned ofs).
    { unfold get_sys_arg1 in Harg1.
      rewrite Harg1 in *; inj.
      rewrite Int.unsigned_repr; auto.
    }
    rewrite Haddr in *.
    assert (Hlen: Int.unsigned i0 = len); subst.
    { unfold get_sys_arg2 in Harg2.
      rewrite Harg2 in *; inj.
      rewrite Int.unsigned_repr; auto.
    }
    assert (0 <= Zlength msg <= Int.max_unsigned).
    { pose proof (Zlength_nonneg msg); cbn; lia. }
    destruct Hpre as (? & Hperm).
    pose proof Hperm as Hperm'.
    apply range_perm_storebytes_less with (bytes := inj_bytes msg) in Hperm as (m' & Hm').
    2: rewrite Zlength_inj_bytes; lia.
    do 7 (esplit; eauto).
    - rewrite Int.unsigned_repr by auto.
      unfold FlatMem.loadbytes, FlatMem.storebytes.
      rewrite ZtoNat_Zlength, <- length_inj_bytes, FlatMem.getN_setN; auto.
    - constructor; eauto; cbn.
      + (* getchars_post *)
        rewrite !Int.unsigned_repr by auto.
        split; try lia.
        exists msg; repeat (split; auto).
        rewrite bytes_to_memvals_inj_bytes.
        exists m'; split; auto.
        eapply mem_equiv_refl.
      + (* trace_itree_match *)
 hnf; intros * Htrace.
        prename (sutt eq _ _) into Htr_eq.
        apply thread_serial_intr_disable_trace_case in Hdisable as (Htr & Heq). (* no difference between log st and log r*)
        cbn in Htr, Heq.
        rename io_log into io_log1.
        SearchAbout r. (* Hread2: thread_cons_buf_read_loop_spec (Int.unsigned i0) z2 r = Some (r0, Zlength msg) *)
        apply thread_cons_buf_read_loop_trace_case in Hread2 as (Htr0 & Heq0).
        (* r and r0 are intermediate. Final goal proving from st to io_log1 *)
        (* st to r, r to r0, r0 to io_log1 *)
        (* prove how to get to *)

        (* for example      : thread_serial_intr_disable_spec st = Some r    from st -> r *)
        admit.
      + (* R_mem *)
        (* TODO: physical mem might not be consecutive, can't use storebytes or
           setN *)
        hnf; intros * Hpaddr Halloc Hperm; subst curid; cbn.
        edestruct sys_getcs_pmap_unchanged as (Hpa & Hpperm); eauto.
        rewrite <- Hpa in Hpaddr; rewrite <- Hpperm in Halloc.
        unfold FlatMem.storebytes.
        hnf in HRmem; subst vaddr; cbn.
        erewrite storebytes_mem_contents; eauto.
        assert (Hperm'' : perm m b ofs0 Cur Nonempty) by (eapply perm_storebytes_2; eauto).
        specialize (HRmem _ _ _ Hpaddr Halloc Hperm'').
        case_eq (eq_block b buf); intros; subst; [rewrite PMap.gss | rewrite PMap.gso by auto].
        * assert ((ofs0 < Ptrofs.unsigned ofs \/ ofs0 >= Ptrofs.unsigned ofs + Z.of_nat (length msg)) \/
                  Ptrofs.unsigned ofs <= ofs0 < Ptrofs.unsigned ofs + Z.of_nat (length msg))
            as [? | ?] by lia.
          { rewrite setN_outside, FlatMem.setN_outside; auto.
            2: rewrite length_inj_bytes; lia.
            admit.
          }
          (* rewrite setN_inside, FlatMem.setN_inside; auto. *)
          (* 2-3: rewrite length_inj_bytes; lia. *)
          (* replace (b2a.(b2a_map) buf + ofs0 - (b2a.(b2a_map) buf + Ptrofs.unsigned ofs)) *)
          (*   with (ofs0 - Ptrofs.unsigned ofs) by lia. *)
          (* destruct (nth _ _ _); auto. *)
          admit.
        * rewrite FlatMem.setN_outside; auto.
          rewrite length_inj_bytes.
          (* eapply block_to_addr_range_perm_disjoint *)
          (*   with (len := length msg) (ofs2 := Ptrofs.unsigned ofs) in Hperm; eauto; try lia. *)
          (* rewrite Z.max_r in Hperm' by lia. *)
          (* eapply range_perm_implies with (p1 := Writable); [| constructor]. *)
          (* rewrite <- Zlength_correct; hnf in Hperm' |- *; intros. *)
          (* eapply Hperm'; lia. *)
          admit.
  Admitted.

  (* TODO: Temporary *)
  Section PrePost.
  Definition mmap_pre (m : mem) (len : Z) := 0 <= len <= Ptrofs.max_unsigned.

  Definition mmap_post (m0 m : mem) r (len : Z) :=
    let res := Mem.alloc m0 0 len in m = fst res /\ r = Vptr (snd res) Ptrofs.zero.
  End PrePost.

  Record R_sys_mmap_correct len m m' st' ret := {
    (* Post condition holds on new state, and result *)
    mmap_post_ok : mmap_post m m' ret len;
    (* The new block is allocated *)
    mmap_mem_ok : R_mem m' st';
  }.

  Context `{FindAddr}.

  Lemma PDX_eq : forall x y,
    x mod PAGE_SIZE = 0 ->
    0 <= y < PAGE_SIZE ->
    PDX x = PDX (x + y).
  Proof.
    unfold PDX; intros; rewrite div_plus; lia.
  Qed.

  Lemma PTX_eq : forall x y,
    x mod PAGE_SIZE = 0 ->
    0 <= y < PAGE_SIZE ->
    PTX x = PTX (x + y).
  Proof.
    unfold PTX; intros; change PAGE_SIZE with (PAGE_SIZE * 1); rewrite div_plus; lia.
  Qed.

  Lemma init_pte_unpresent : forall len i, 0 <= i <= Z.of_nat len ->
    ZMap.get i (Calculate_init_pte len) = PTEUnPresent.
  Proof.
    induction len; cbn -[Z.of_nat]; intros.
    { assert (i = 0) by lia; subst.
      rewrite ZMap.gss; auto.
    }
    assert (0 <= i <= Z.of_nat len \/ i = Z.of_nat (S len)) as [? | ?] by lia;
      subst; [rewrite ZMap.gso by lia | rewrite ZMap.gss]; auto.
  Qed.

  Lemma ptRead_spec_same_page : forall st pid vaddr ofs paddr,
    let vaddr' := vaddr + ofs in
    paddr <> 0 ->
    PDX vaddr = PDX vaddr' ->
    PTX vaddr = PTX vaddr' ->
    ptRead_spec pid vaddr st = Some paddr ->
    ptRead_spec pid vaddr' st = Some paddr.
  Proof.
    unfold ptRead_spec; intros * ? Hpdx Hptx Hpaddr.
    destruct_spec Hpaddr; try easy.
    prename getPDE_spec into Hpde.
    rewrite <- Hptx, <- Hpdx, Hpde.
    destruct (Coqlib.zeq _ _); try easy.
    now destruct (zlt_lt _ _ _).
  Qed.

  Lemma get_kernel_pa_same_page : forall st pid vaddr ofs paddr,
    let vaddr' := vaddr + ofs in
    (* TODO: stronger than necessary *)
    vaddr mod PAGE_SIZE = 0 -> 0 <= ofs < PAGE_SIZE ->
    get_kernel_pa_spec pid vaddr st = Some paddr ->
    get_kernel_pa_spec pid vaddr' st = Some (paddr + ofs).
  Proof.
    unfold get_kernel_pa_spec; intros * ? ? Hpaddr.
    destruct_spec Hpaddr.
    erewrite ptRead_spec_same_page; eauto using PDX_eq, PTX_eq.
    destruct (Coqlib.zeq z 0); try easy.
    enough ((vaddr + ofs) mod PAGE_SIZE = vaddr mod PAGE_SIZE + ofs) as ->; auto with zarith.
    rewrite <- (Z.mod_small (vaddr mod PAGE_SIZE + ofs) PAGE_SIZE) by lia.
    rewrite Z.add_mod_idemp_l; lia.
  Qed.

  Lemma big2_palloc_spec_mem_changed : forall st st' n pi,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    big2_palloc_spec n st = Some (st', pi) ->
    pid = pid' /\
    st.(HP) = st'.(HP) /\
    (forall vaddr, get_kernel_pa_spec pid vaddr st = get_kernel_pa_spec pid' vaddr st') /\
    (forall pi',
      (pi = pi' -> pi' <> 0 -> ZMap.get pi' st'.(pperm) = PGAlloc) /\
      (pi = 0 -> st.(pperm) = st'.(pperm)) /\
      (pi <> pi' -> ZMap.get pi' st.(pperm) = ZMap.get pi' st'.(pperm))).
  Proof.
    unfold big2_palloc_spec; intros * Hspec; destruct_spec Hspec.
    all: destruct st; cbn in *; repeat (split; auto); intros; subst; try easy.
    - rewrite ZMap.gss; auto.
    - prename find_paddr into Hpaddr.
      eapply find_paddr_spec in Hpaddr; easy.
    - rewrite ZMap.gso; auto.
  Qed.

  Lemma big2_ptInsertPTE0_spec_mem_changed : forall st st' n vaddr pi p,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    big2_ptInsertPTE0_spec n vaddr pi p st = Some st' ->
    pid = pid' /\
    st.(HP) = st'.(HP) /\
    (forall vaddr',
      (pid = n -> PDX vaddr = PDX vaddr' -> PTX vaddr = PTX vaddr' ->
        get_kernel_pa_spec pid' vaddr' st' = Some (PAGE_SIZE * pi + vaddr' mod PAGE_SIZE)) /\
      (pid <> n \/ PDX vaddr <> PDX vaddr' ->
        get_kernel_pa_spec pid vaddr' st = get_kernel_pa_spec pid' vaddr' st')) /\
    st.(pperm) = st'.(pperm).
  Proof.
    unfold big2_ptInsertPTE0_spec; intros * Hspec; destruct_spec Hspec.
    all: destruct st; cbn in *; repeat (split; auto).
    - intros ? Hpdx Hptx; subst.
      unfold get_kernel_pa_spec, ptRead_spec, getPDE_spec, PTE_Arg, PDE_Arg; cbn.
      destruct (zle_lt _ _ _).
      2: admit. (* TODO: OS invariant, curid in range *)
      destruct (zle_le _ _ _).
      2: admit. (* TODO: OS invariant, vaddr range *)
      rewrite Hpdx, Hptx, !ZMap.gss.
      destruct (Coqlib.zeq _ _).
      admit. (* TODO: OS invariant, PDEValid pi <> 0 *)
      destruct (zlt_lt _ _ _).
      2: admit. (* TODO: OS invariant, PDEValid pi range *)
      unfold PTE_Arg, PDE_Arg.
      destruct (zle_lt _ _ _); try lia.
      destruct (zle_le _ _ _).
      2: cbn in *; lia.
      destruct (zle_le _ _ _); try lia.
      2: admit. (* TODO: OS invariant, vaddr range *)
      destruct (Coqlib.zeq _ _).
      { destruct p; cbn [PermToZ] in *; try lia.
        destruct b; lia.
      }
      enough ((pi * PAGE_SIZE + PermToZ p) / PAGE_SIZE * PAGE_SIZE = PAGE_SIZE * pi) as ->; auto.
      rewrite Z.mul_comm, Z.mul_cancel_l, Z.div_add_l by lia.
      destruct p; cbn; try lia.
      destruct b; cbn; lia.
    - intros Hneq; unfold get_kernel_pa_spec, ptRead_spec; cbn.
      destruct Hneq.
      { rewrite ZMap.gso; auto. }
      destruct (Coqlib.zeq (ZMap.get CPU_ID cid) n); subst.
      2: rewrite ZMap.gso; auto.
      rewrite ZMap.gss, ZMap.gso; auto.
    - intros ? Hpdx Hptx; subst.
      unfold get_kernel_pa_spec, ptRead_spec, getPDE_spec, PTE_Arg, PDE_Arg; cbn.
      destruct (zle_lt _ _ _).
      2: admit. (* TODO: OS invariant, curid in range *)
      destruct (zle_le _ _ _).
      2: admit. (* TODO: OS invariant, vaddr range *)
      rewrite Hpdx, Hptx, !ZMap.gss.
      destruct (Coqlib.zeq _ _).
      admit. (* TODO: OS invariant, PDEValid pi <> 0 *)
      destruct (zlt_lt _ _ _).
      2: admit. (* TODO: OS invariant, PDEValid pi range *)
      unfold PTE_Arg, PDE_Arg.
      destruct (zle_lt _ _ _); try lia.
      destruct (zle_le _ _ _).
      2: cbn in *; lia.
      destruct (zle_le _ _ _); try lia.
      2: admit. (* TODO: OS invariant, vaddr range *)
      destruct (Coqlib.zeq _ _).
      { destruct p; cbn [PermToZ] in *; try lia.
        destruct b; lia.
      }
      enough ((pi * PAGE_SIZE + PermToZ p) / PAGE_SIZE * PAGE_SIZE = PAGE_SIZE * pi) as ->; auto.
      rewrite Z.mul_comm, Z.mul_cancel_l, Z.div_add_l by lia.
      destruct p; cbn; try lia.
      destruct b; cbn; lia.
    - intros Hneq; unfold get_kernel_pa_spec, ptRead_spec; cbn.
      destruct Hneq.
      { rewrite ZMap.gso; auto. }
      destruct (Coqlib.zeq (ZMap.get CPU_ID cid) n); subst.
      2: rewrite ZMap.gso; auto.
      rewrite ZMap.gss, ZMap.gso; auto.
  Admitted.

  Lemma big2_ptAllocPDE_spec_mem_changed : forall st st' n vaddr pi,
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    big2_ptAllocPDE_spec n vaddr st = Some (st', pi) ->
    pid = pid' /\
    (pi = 0 ->
      st.(HP) = st'.(HP) /\
      (forall vaddr', get_kernel_pa_spec pid vaddr' st = get_kernel_pa_spec pid' vaddr' st') /\
      st.(pperm) = st'.(pperm)) /\
    (pi <> 0 ->
      FlatMem.free_page pi st.(HP) = st'.(HP) /\
      (forall vaddr',
        (pid = n -> PDX vaddr = PDX vaddr' ->
          get_kernel_pa_spec pid' vaddr' st' = None) /\
        (pid <> n \/ PDX vaddr <> PDX vaddr' ->
          get_kernel_pa_spec pid vaddr' st = get_kernel_pa_spec pid' vaddr' st')) /\
      (forall pi',
        (pi = pi' -> ZMap.get pi' st'.(pperm) = PGHide (PGPMap n (PDX vaddr))) /\
        (pi <> pi' -> ZMap.get pi' st.(pperm) = ZMap.get pi' st'.(pperm)))).
  Proof.
    unfold big2_ptAllocPDE_spec; intros * Hspec; destruct_spec Hspec.
    - prename big2_palloc_spec into Hspec.
      apply big2_palloc_spec_mem_changed in Hspec.
      split; [| split]; intros; try easy.
      destruct Hspec as (? & ? & ? & Hperm).
      repeat (split; auto).
      apply Hperm; auto.
    - prename big2_palloc_spec into Hspec.
      apply big2_palloc_spec_mem_changed in Hspec.
      destruct Hspec as (-> & <- & Haddr & Hperm).
      split; [| split]; intros; try easy.
      { destruct r; auto. }
      split; [| split].
      + destruct r; cbn -[FlatMem.free_page real_init_PTE]; auto.
      + intros; split.
        * intros ? Hpdx; subst.
          destruct r; cbn -[FlatMem.free_page real_init_PTE] in *.
          unfold get_kernel_pa_spec, ptRead_spec, getPDE_spec, PTE_Arg, PDE_Arg; cbn -[real_init_PTE].
          destruct pg, ikern, ihost, init, ipt; auto.
          destruct (zle_lt _ _ _); auto.
          destruct (zle_le _ _ _); auto.
          rewrite Hpdx, !ZMap.gss.
          destruct (Coqlib.zeq _ _); auto.
          destruct (zlt_lt _ _ _); auto.
          destruct (PTE_Arg _ _ _); auto.
          replace (ZMap.get (PTX vaddr') real_init_PTE) with PTEUnPresent; auto.
          unfold real_init_PTE.
          rewrite init_pte_unpresent; auto.
          unfold PTX; rewrite Z2Nat.id by lia.
          pose proof (Z.mod_pos_bound (vaddr' / PAGE_SIZE) 1024); lia.
        * intros Hneq.
          rewrite Haddr.
          destruct r; unfold get_kernel_pa_spec, ptRead_spec; cbn -[FlatMem.free_page real_init_PTE].
          destruct pg, ikern, ihost, init, ipt; auto.
          destruct (PDE_Arg _ _); auto.
          destruct Hneq.
          { rewrite ZMap.gso; auto. }
          destruct (Coqlib.zeq (ZMap.get CPU_ID cid) n); subst.
          2: rewrite ZMap.gso; auto.
          rewrite ZMap.gss, ZMap.gso; auto.
      + destruct r; cbn -[FlatMem.free_page real_init_PTE]; auto.
        split; intros; subst.
        * rewrite ZMap.gss; eauto.
        * cbn in Hperm; specialize (Hperm pi').
          destruct Hperm as (_ & _ & Hperm).
          rewrite ZMap.gso; auto.
  Qed.

  Lemma big2_ptInsert_spec_mem_changed : forall st st' n vaddr pi p pi',
    let pid := ZMap.get st.(CPU_ID) st.(cid) in
    let pid' := ZMap.get st'.(CPU_ID) st'.(cid) in
    big2_ptInsert_spec n vaddr pi p st = Some (st', pi') ->
    pid = pid' /\
    (pi' = 0 ->
      st.(HP) = st'.(HP) /\
      (forall vaddr',
        (pid = n -> PDX vaddr = PDX vaddr' -> PTX vaddr = PTX vaddr' ->
          get_kernel_pa_spec pid' vaddr' st' = Some (PAGE_SIZE * pi + vaddr' mod PAGE_SIZE)) /\
        (pid <> n \/ PDX vaddr <> PDX vaddr' ->
          get_kernel_pa_spec pid vaddr' st = get_kernel_pa_spec pid' vaddr' st')) /\
      st.(pperm) = st'.(pperm)) /\
    (pi' = MAGIC_NUMBER ->
      st.(HP) = st'.(HP) /\
      (forall vaddr', get_kernel_pa_spec pid vaddr' st = get_kernel_pa_spec pid' vaddr' st') /\
      st.(pperm) = st'.(pperm)) /\
    (pi' <> 0 /\ pi' <> MAGIC_NUMBER ->
      FlatMem.free_page pi' st.(HP) = st'.(HP) /\
      (forall vaddr',
        (pid = n -> PDX vaddr = PDX vaddr' -> PTX vaddr = PTX vaddr' ->
          get_kernel_pa_spec pid' vaddr' st' = Some (PAGE_SIZE * pi + vaddr' mod PAGE_SIZE)) /\
        (pid <> n \/ PDX vaddr <> PDX vaddr' ->
          get_kernel_pa_spec pid vaddr' st = get_kernel_pa_spec pid' vaddr' st')) /\
      (forall pi'',
        (pi' = pi'' -> ZMap.get pi' st'.(pperm) = PGHide (PGPMap n (PDX vaddr))) /\
        (pi' <> pi'' -> ZMap.get pi'' st.(pperm) = ZMap.get pi'' st'.(pperm)))).
  Proof.
    unfold big2_ptInsert_spec; intros * Hspec; destruct_spec Hspec.
    - prename big2_ptInsertPTE0_spec into Hspec.
      apply big2_ptInsertPTE0_spec_mem_changed in Hspec.
      easy.
    - prename big2_ptAllocPDE_spec into Hspec.
      apply big2_ptAllocPDE_spec_mem_changed in Hspec.
      split; [| split; [| split]]; intros; try easy.
      apply Hspec; auto.
    - assert (pi' <> MAGIC_NUMBER) by admit. (* TODO: OS invariant *)
      prename big2_ptAllocPDE_spec into Hspec.
      apply big2_ptAllocPDE_spec_mem_changed in Hspec.
      prename big2_ptInsertPTE0_spec into Hspec'.
      apply big2_ptInsertPTE0_spec_mem_changed in Hspec'.
      destruct Hspec as (-> & _ & (-> & Haddr & Hperm)); auto.
      destruct Hspec' as (Hpid & -> & Haddr' & Hperm').
      rewrite Hpid in *.
      split; [| split; [|split ]]; intros; auto; try easy.
      repeat (split; auto).
      + intros; subst.
        apply Haddr'; auto.
      + intros.
        edestruct Haddr as (_ & ->); eauto.
        apply Haddr'; auto; congruence.
      + intros; subst.
        rewrite <- Hperm'.
        apply Hperm; auto.
      + intros.
        rewrite <- Hperm'.
        apply Hperm; auto.
  Admitted.

  Lemma sys_mmap_correct len m st st' :
    R_mem m st ->
    (* Pre condition holds *)
    mmap_pre m len ->
    (* len is passed as an argument *)
    get_sys_arg1 st = Vint (Int.repr len) ->
    (* sys_mmap returns some state *)
    sys_mmap_spec st = Some st' ->
    exists ret,
      get_sys_ret st' = Vint ret /\
      let b' := m.(nextblock) in
      b2a.(b2a_map) b' = Int.unsigned ret ->
      exists m',
        R_sys_mmap_correct len m m' st' (Vptr b' Ptrofs.zero).
  Proof.
    unfold mmap_pre, get_sys_arg1, get_sys_ret; intros HRmem Hpre Harg Hspec.
    pose proof Hspec.
    unfold sys_mmap_spec, uctx_set_errno_spec in Hspec; destruct_spec Hspec.
    prename uctx_set_retval1_spec into Hret.
    unfold uctx_set_retval1_spec in Hret; destruct_spec Hret.
    prename uctx_arg2_spec into Hspec.
    unfold uctx_arg2_spec in Hspec; destruct_spec Hspec.
    prename big2_ptResv_spec into Hspec.
    unfold big2_ptResv_spec in Hspec; destruct_spec Hspec.
    prename get_kernel_pa_spec into Hpaddr.
    destruct r; cbn -[big2_ptInsert_spec] in *.
    repeat (rewrite ZMap.gss in * || rewrite ZMap.gso in * by easy); subst; inj.
    do 2 esplit; eauto; intros.
    prename Coqlib.zlt into Htmp; clear Htmp. (* rewrite fails on len < PAGE_SIZE otherwise *)
    rewrite Int.unsigned_repr in * by functional_base.rep_omega.
    prename big2_palloc_spec into Hspec'; pose proof Hspec' as Htmp.
    apply big2_palloc_spec_mem_changed in Htmp as (Hpid & Hmem_eq & Haddr_eq & Hperm_eq).
    pose proof Hspec as Htmp.
    apply big2_ptInsert_spec_mem_changed in Htmp.
    cbn -[FlatMem.free_page get_kernel_pa_spec] in Htmp.
    destruct Htmp as (Hpid' & Hcase1 & _ & Hcase2).
    rewrite Hpid, Hpid' in *.
    esplit; constructor; hnf; eauto.
    (* R_mem *)
    cbn -[get_kernel_pa_spec].
    intros * Hpaddr' Halloc Hperm.
    assert (alloc m 0 len = (fst (alloc m 0 len), m.(nextblock))).
    { Local Transparent alloc. unfold alloc; cbn; auto. Local Opaque alloc. }
    eapply perm_alloc_inv in Hperm; eauto.
    destruct (eq_block b m.(nextblock)); subst.
    - erewrite mem_lemmas.AllocContentsUndef1; eauto.
      destruct (Coqlib.zeq z1 0); subst.
      + destruct Hcase1 as (? & Haddr_eq' & ?); subst; auto.
        rewrite <- Hmem_eq.
        rewrite FlatMem.setN_inside.
        { rewrite data_at_rec_lemmas.nth_list_repeat; auto. }
        rewrite Coqlib.length_list_repeat, Z2Nat.id; try lia.
        rewrite get_kernel_pa_same_page with (paddr := z2) in Hpaddr'; inj; try lia; auto.
      + destruct Hcase2 as (? & Haddr_eq' & Hperm_eq'); subst; auto.
        rewrite <- Hmem_eq.
        rewrite FlatMem.setN_inside.
        { rewrite data_at_rec_lemmas.nth_list_repeat; auto. }
        rewrite Coqlib.length_list_repeat, Z2Nat.id; try lia.
        rewrite get_kernel_pa_same_page with (paddr := z2) in Hpaddr'; inj; try lia; auto.
    - assert (z <> paddr / PAGE_SIZE) by admit. (* TODO: OS invariant *)
      assert (z1 <> paddr / PAGE_SIZE) by admit. (* TODO: OS invariant *)
      erewrite mem_lemmas.AllocContentsOther; eauto.
      hnf in HRmem; cbn in HRmem; specialize (HRmem b ofs paddr).
      rewrite Hpid, Hmem_eq, Haddr_eq in HRmem.
      specialize (Hperm_eq (paddr / PAGE_SIZE)).
      destruct Hperm_eq as (_ & _ & Hperm_eq).
      rewrite Hperm_eq in HRmem; auto.
      destruct (Coqlib.zeq z1 0); subst.
      + destruct Hcase1 as (? & Haddr_eq' & ?); subst; auto.
        specialize (Haddr_eq' (b2a.(b2a_map) b + ofs)).
        destruct Haddr_eq' as (_ & Haddr_eq').
        (* TODO: arith *)
        assert (Hpdx: PDX (b2a_map b2a (nextblock m)) <> PDX (b2a_map b2a b + ofs)) by admit.
        specialize (Haddr_eq' (or_intror Hpdx)).
        rewrite Haddr_eq', Hpaddr' in HRmem.
        rewrite FlatMem.setN_outside.
        apply HRmem; auto.
        rewrite Coqlib.length_list_repeat, Z2Nat.id by lia.
        admit. (* TODO: arith *)
      + destruct Hcase2 as (? & Haddr_eq' & Hperm_eq'); subst; auto.
        specialize (Haddr_eq' (b2a.(b2a_map) b + ofs)).
        destruct Haddr_eq' as (_ & Haddr_eq').
        (* TODO: arith *)
        assert (Hpdx: PDX (b2a_map b2a (nextblock m)) <> PDX (b2a_map b2a b + ofs)) by admit.
        specialize (Haddr_eq' (or_intror Hpdx)).
        rewrite Haddr_eq', Hpaddr' in HRmem.
        specialize (HRmem ltac:(auto)).
        specialize (Hperm_eq' (paddr / PAGE_SIZE)).
        destruct Hperm_eq' as (_ & Hperm_eq').
        rewrite Hperm_eq' in HRmem; auto.
        unfold FlatMem.free_page; rewrite !FlatMem.setN_outside.
        apply HRmem; auto.
        all: rewrite Coqlib.length_list_repeat, Z2Nat.id by lia.
        admit. admit. (* TODO: arith *)
  Admitted.

End SpecsCorrect.
