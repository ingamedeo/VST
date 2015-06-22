Require Import floyd.base.
Require floyd.fieldlist. Import floyd.fieldlist.fieldlist.
Open Scope nat.

Inductive ListType: list Type -> Type :=
  | Nil: ListType nil
  | Cons: forall {A B} (a: A) (b: ListType B), ListType (A :: B).

Fixpoint ListTypeGen {A} (F: A -> Type) (f: forall A, F A) (l: list A) : ListType (map F l) :=
  match l with
  | nil => Nil
  | cons h t => Cons (f h) (ListTypeGen F f t)
  end.

Lemma ListTypeGen_preserve: forall A F f1 f2 (l: list A),
  (forall a, In a l -> f1 a = f2 a) ->
  ListTypeGen F f1 l = ListTypeGen F f2 l.
Proof.
  intros.
  induction l.
  + reflexivity.
  + simpl.
    rewrite H, IHl.
    - reflexivity.
    - intros; apply H; simpl; tauto.
    - simpl; left; auto.
Defined.

Definition decay' {X} {F: Type} {l: list X} (v: ListType (map (fun _ => F) l)): list F.
  remember (map (fun _ : X => F) l) eqn:E.
  revert l E.
  induction v; intros.
  + exact nil.
  + destruct l; inversion E.
    specialize (IHv l H1).
    rewrite H0 in a.
    exact (a :: IHv).
Defined.

Fixpoint decay'' {X} {F: Type} (l0 : list Type) (v: ListType l0) :
  forall (l: list X), l0 = map (fun _ => F) l -> list F :=
  match v in ListType l1
    return forall l2, l1 = map (fun _ => F) l2 -> list F
  with
  | Nil => fun _ _ => nil
  | Cons A B a b =>
    fun (l1 : list X) (E0 : A :: B = map (fun _ : X => F) l1) =>
    match l1 as l2 return (A :: B = map (fun _ : X => F) l2 -> list F) with
    | nil => fun _ => nil (* impossible case *)
    | x :: l2 =>
       fun E1 : A :: B = map (fun _ : X => F) (x :: l2) =>
       (fun
          X0 : map (fun _ : X => F) (x :: l2) =
               map (fun _ : X => F) (x :: l2) -> list F => 
        X0 eq_refl)
         match
           E1 in (_ = y)
           return (y = map (fun _ : X => F) (x :: l2) -> list F)
         with
         | eq_refl =>
             fun H0 : A :: B = map (fun _ : X => F) (x :: l2) =>
              (fun (H3 : A = F) (H4 : B = map (fun _ : X => F) l2) =>
                  (eq_rect A (fun A0 : Type => A0) a F H3) :: (decay'' B b l2 H4))
                 (f_equal
                    (fun e : list Type =>
                     match e with
                     | nil => A
                     | T :: _ => T
                     end) H0)
                (f_equal
                   (fun e : list Type =>
                    match e with
                    | nil => B
                    | _ :: l3 => l3
                    end) H0)
         end
    end E0
  end.

Definition decay {X} {F: Type} {l: list X} (v: ListType (map (fun _ => F) l)): list F :=
  let l0 := map (fun _ => F) l in 
  let E := @eq_refl _ (map (fun _ => F) l) : l0 = map (fun _ => F) l in
  decay'' l0 v l E.

Lemma decay_spec: forall A F f l,
  decay (ListTypeGen (fun _: A => F) f l) = map f l.
Proof.
  intros.
  unfold decay.
  induction l.
  + simpl.
    reflexivity.
  + simpl.
    f_equal.
    auto.
Defined.

Section COMPOSITE_ENV.
Context {cs: compspecs}.
Context {csl: compspecs_legal cs}.

Lemma type_ind: forall P,
  (forall t,
  match t with
  | Tarray t0 _ _ => P t0
  | Tstruct id _ => Forall (fun it => P (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id))
  | Tunion id _ => Forall (fun it => P (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id))
  | _ => True
  end -> P t) ->
  forall t, P t.
Proof.
  intros P IH_TYPE.
  intros.
  remember (rank_type cenv_cs t) as n eqn: RANK'.
  assert (rank_type cenv_cs t <= n)%nat as RANK by omega; clear RANK'.
  revert t RANK.
  induction n;
  intros;
  specialize (IH_TYPE t); destruct t;
  try solve [specialize (IH_TYPE I); auto].
  + (* Tarray level 0 *)
    simpl in RANK. omega.
  + (* Tstruct level 0 *)
    simpl in RANK.
    unfold get_co in IH_TYPE.
    destruct (cenv_cs ! i); [omega | apply IH_TYPE].
    simpl; constructor.
  + (* Tunion level 0 *)
    simpl in RANK.
    unfold get_co in IH_TYPE.
    destruct (cenv_cs ! i); [omega | apply IH_TYPE].
    simpl; constructor.
  + (* Tarray level positive *)
    simpl in RANK.
    specialize (IHn t).
    apply IH_TYPE, IHn.
    omega.
  + (* Tstruct level positive *)
    simpl in RANK.
    pose proof get_co_members_no_replicate i.
    unfold get_co in *.
    destruct (cenv_cs ! i) as [co |] eqn:CO; [| apply IH_TYPE; simpl; constructor].
    apply IH_TYPE; clear IH_TYPE.
    apply Forall_forall.
    intros [i0 t0] ?; simpl.
    apply IHn.
    pose proof In_field_type _ _ H H0.
    simpl in H1; rewrite H1.
    apply rank_type_members with (ce := cenv_cs) in H0.
    rewrite <- co_consistent_rank in H0; [omega |].
    exact (cenv_consistent_cs i co CO).
  + (* Tunion level positive *)
    simpl in RANK.
    pose proof get_co_members_no_replicate i.
    unfold get_co in *.
    destruct (cenv_cs ! i) as [co |] eqn:CO; [| apply IH_TYPE; simpl; constructor].
    apply IH_TYPE; clear IH_TYPE.
    apply Forall_forall.
    intros [i0 t0] ?; simpl.
    apply IHn.
    pose proof In_field_type _ _ H H0.
    simpl in H1; rewrite H1.
    apply rank_type_members with (ce := cenv_cs) in H0.
    rewrite <- co_consistent_rank in H0; [omega |].
    exact (cenv_consistent_cs i co CO).
Defined.

Ltac type_induction t :=
  pattern t;
  match goal with
  | |- ?P t =>
    apply type_ind; clear t;
    let t := fresh "t" in
    intros t IH;
    let id := fresh "id" in
    let a := fresh "a" in
    destruct t as [| | | | | | | id a | id a]
  end.

Variable A: type -> Type.
Variable F_ByValue: forall t: type, A t.
Variable F_Tarray: forall t n a, A t -> A (Tarray t n a).
Variable F_Tstruct: forall id a, ListType (map (fun it => A (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id))) -> A (Tstruct id a).
Variable F_Tunion: forall id a, ListType (map (fun it => A (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id))) -> A (Tunion id a).

Fixpoint func_type_rec (n: nat) (t: type): A t :=
  match n with
  | 0 =>
    match t as t0 return A t0 with
    | Tstruct id a =>
       match cenv_cs ! id with
       | None => F_Tstruct id a (ListTypeGen (fun it => A (field_type (fst it) (co_members (get_co id)))) (fun it => F_ByValue (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id)))
       | _ => F_ByValue (Tstruct id a)
       end
    | Tunion id a =>
       match cenv_cs ! id with
       | None => F_Tunion id a (ListTypeGen (fun it => A (field_type (fst it) (co_members (get_co id)))) (fun it => F_ByValue (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id)))
       | _ => F_ByValue (Tunion id a)
       end
    | t' => F_ByValue t'
    end
  | S n' =>
    match t as t0 return A t0 with
    | Tarray t0 n a => F_Tarray t0 n a (func_type_rec n' t0)
    | Tstruct id a => F_Tstruct id a (ListTypeGen (fun it => A (field_type (fst it) (co_members (get_co id)))) (fun it => func_type_rec n' (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id)))
    | Tunion id a => F_Tunion id a (ListTypeGen (fun it => A (field_type (fst it) (co_members (get_co id)))) (fun it => func_type_rec n' (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id)))
    | t' => F_ByValue t'
    end
  end.

Definition func_type t := func_type_rec (rank_type cenv_cs t) t.

Lemma rank_type_Tstruct: forall id a co, cenv_cs ! id = Some co ->
  rank_type cenv_cs (Tstruct id a) = S (co_rank (get_co id)).
Proof.
  intros.
  unfold get_co; simpl.
  destruct (cenv_cs ! id); auto; congruence.
Defined.

Lemma rank_type_Tunion: forall id a co, cenv_cs ! id = Some co ->
  rank_type cenv_cs (Tunion id a) = S (co_rank (get_co id)).
Proof.
  intros.
  unfold get_co; simpl.
  destruct (cenv_cs ! id); auto; congruence.
Defined.

Lemma func_type_rec_rank_irrelevent: forall t n n0,
  n >= rank_type cenv_cs t ->
  n0 >= rank_type cenv_cs t ->
  func_type_rec n t = func_type_rec n0 t.
Proof.
  intros t.
  type_induction t;
  intros; try solve [destruct n, n0; simpl; auto].
  + (* Tarray *)
    destruct n; simpl in H; [omega |].
    destruct n0; simpl in H0; [omega |].
    specialize (IH n n0); do 2 (spec IH; [omega |]).
    simpl.
    rewrite IH.
    reflexivity.
  + (* Tstruct *)
    destruct (cenv_cs ! id) as [co |] eqn: CO.
    - erewrite rank_type_Tstruct in H by eauto.
      erewrite rank_type_Tstruct in H0 by eauto.
      clear co CO.
      destruct n, n0; try omega.
      simpl.
      f_equal.
      apply ListTypeGen_preserve.
      intros [i t] Hin.
      rewrite Forall_forall in IH.
      specialize (IH (i, t) Hin n n0).
      pose proof get_co_members_no_replicate id.
      pose proof In_field_type (i, t) _ H1 Hin.
      rewrite H2 in IH |- *.
      simpl in IH |- *.
      pose proof rank_type_members cenv_cs i t _ Hin.
      rewrite co_consistent_rank with (env := cenv_cs) in H by apply get_co_consistent.
      rewrite co_consistent_rank with (env := cenv_cs) in H0 by apply get_co_consistent.
      apply IH; omega.
    - destruct n, n0; simpl;
      generalize (F_Tstruct id a) as FF; unfold get_co;
      rewrite CO; intros; auto.
  + (* Tunion *)
    destruct (cenv_cs ! id) as [co |] eqn: CO.
    - erewrite rank_type_Tunion in H by eauto.
      erewrite rank_type_Tunion in H0 by eauto.
      clear co CO.
      destruct n, n0; try omega.
      simpl.
      f_equal.
      apply ListTypeGen_preserve.
      intros [i t] Hin.
      rewrite Forall_forall in IH.
      specialize (IH (i, t) Hin n n0).
      pose proof get_co_members_no_replicate id.
      pose proof In_field_type (i, t) _ H1 Hin.
      rewrite H2 in IH |- *.
      simpl in IH |- *.
      pose proof rank_type_members cenv_cs i t _ Hin.
      rewrite co_consistent_rank with (env := cenv_cs) in H by apply get_co_consistent.
      rewrite co_consistent_rank with (env := cenv_cs) in H0 by apply get_co_consistent.
      apply IH; omega.
    - destruct n, n0; simpl;
      generalize (F_Tunion id a) as FF; unfold get_co;
      rewrite CO; intros; auto.
Defined.

Lemma func_type_ind: forall t, 
  func_type t = 
  match t as t0 return A t0 with
  | Tarray t0 n a => F_Tarray t0 n a (func_type t0)
  | Tstruct id a => F_Tstruct id a (ListTypeGen (fun it => A (field_type (fst it) (co_members (get_co id)))) (fun it => func_type (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id)))
  | Tunion id a => F_Tunion id a (ListTypeGen (fun it => A (field_type (fst it) (co_members (get_co id)))) (fun it => func_type (field_type (fst it) (co_members (get_co id)))) (co_members (get_co id)))
  | t' => F_ByValue t'
  end.
Proof.
  intros.
  type_induction t; try solve [simpl; auto].
  + (* Tstruct *)
    unfold func_type in *.
    simpl.
    destruct (cenv_cs ! id) as [co |] eqn:CO; simpl.
    - f_equal.
      apply ListTypeGen_preserve.
      unfold get_co; rewrite CO.
      intros [i t] Hin.
      rewrite Forall_forall in IH.
      pose proof cenv_consistent_cs id co CO.
      apply func_type_rec_rank_irrelevent.
      * pose proof get_co_members_no_replicate id.
        unfold get_co in H0; rewrite CO in H0.
        pose proof In_field_type _ _ H0 Hin.
        rewrite H1.
        rewrite co_consistent_rank with (env := cenv_cs) by auto.
        eapply rank_type_members; eauto.
      * omega.
    - rewrite CO.
      f_equal.
      unfold get_co; rewrite CO.
      reflexivity.
  + (* Tunion *)
    unfold func_type in *.
    simpl.
    destruct (cenv_cs ! id) as [co |] eqn:CO; simpl.
    - f_equal.
      apply ListTypeGen_preserve.
      unfold get_co; rewrite CO.
      intros [i t] Hin.
      pose proof cenv_consistent_cs id co CO.
      apply func_type_rec_rank_irrelevent.
      * pose proof get_co_members_no_replicate id.
        unfold get_co in H0; rewrite CO in H0.
        pose proof In_field_type _ _ H0 Hin.
        rewrite H1.
        rewrite co_consistent_rank with (env := cenv_cs) by auto.
        eapply rank_type_members; eauto.
      * omega.
    - rewrite CO.
      f_equal.
      unfold get_co; rewrite CO.
      reflexivity.
Defined.

End COMPOSITE_ENV.

Arguments func_type {cs} A F_ByValue F_Tarray F_Tstruct F_Tunion t / .

Ltac type_induction t :=
  pattern t;
  match goal with
  | |- ?P t =>
    apply type_ind; clear t;
    let t := fresh "t" in
    intros t IH;
    let id := fresh "id" in
    let a := fresh "a" in
    destruct t as [| | | | | | | id a | id a]
  end.
