open import Haskell.Prelude as Prelude
open import Scope
open import Utils.Tactics using (auto)

open import Agda.Core.GlobalScope using (Globals; Name)
open import Agda.Core.Signature
open import Agda.Core.Syntax as Syntax
open import Agda.Core.Substitute
open import Agda.Core.Context
open import Agda.Core.Conversion
open import Agda.Core.Reduce
open import Agda.Core.TCM
open import Agda.Core.TCMInstances
open import Agda.Core.Utils

open import Haskell.Extra.Erase
open import Haskell.Extra.Dec
open import Haskell.Law.Eq
open import Haskell.Law.Equality

module Agda.Core.Converter
    {{@0 globals : Globals}}
    {{@0 sig     : Signature}}
  where

private open module @0 G = Globals globals

private variable
  @0 x y : Name
  @0 α β : Scope Name

reduceTo : {@0 α : Scope Name} (r : Rezz α) (v : Term α)
         → TCM (∃[ t ∈ Term α ] (ReducesTo v t))
reduceTo r v = do
  f ← tcmFuel
  rsig ← tcmSignature
  case reduce r rsig v f of λ where
    Nothing        → tcError "not enough fuel to reduce a term"
    (Just u) ⦃ p ⦄ → return $ u ⟨ ⟨ r ⟩ ⟨ rsig ⟩ f ⟨ p ⟩ ⟩
{-# COMPILE AGDA2HS reduceTo #-}

convVars : (@0 x y : Name)
           {@(tactic auto) p : x ∈ α} {@(tactic auto) q : y ∈ α}
         → TCM (Conv (TVar x) (TVar y))
convVars x y {p} {q} =
  ifDec (decIn p q)
    (λ where {{refl}} → return CRefl)
    (tcError "variables not convertible")
{-# COMPILE AGDA2HS convVars #-}

convDefs : (@0 f g : Name)
           {@(tactic auto) p : f ∈ defScope}
           {@(tactic auto) q : g ∈ defScope}
         → TCM (Conv {α = α} (TDef f) (TDef g))
convDefs f g {p} {q} =
  ifDec (decIn p q)
    (λ where {{refl}} → return CRefl)
    (tcError "definitions not convertible")
{-# COMPILE AGDA2HS convDefs #-}

convSorts : (u u' : Sort α)
          → TCM (Conv (TSort u) (TSort u'))
convSorts (STyp u) (STyp u') =
  ifDec ((u == u') ⟨ isEquality u u' ⟩)
    (λ where {{refl}} → return $ CRefl)
    (tcError "can't convert two different sorts")
{-# COMPILE AGDA2HS convSorts #-}

convertCheck : Fuel → Rezz α → (t q : Term α) → TCM (t ≅ q)
convertSubsts : Fuel → Rezz α →
                (s p : β ⇒ α)
              → TCM (s ⇔ p)
convertBranches : Fuel → Rezz α →
                ∀ {@0 cons : Scope Name}
                  (bs bp : Branches α cons)
                → TCM (ConvBranches bs bp)

convDatas : Fuel → Rezz α →
           (@0 d e : Name)
           {@(tactic auto) dp : d ∈ dataScope}
           {@(tactic auto) ep : e ∈ dataScope}
           (ps : dataParScope d ⇒ α) (qs : dataParScope e ⇒ α)
           (is : dataIxScope d ⇒ α) (ks : dataIxScope e ⇒ α)
         → TCM (Conv (TData d ps is) (TData e qs ks))
convDatas fl r d e {dp} {ep} ps qs is ks = do
  ifDec (decIn dp ep)
    (λ where {{refl}} → do
      cps ← convertSubsts fl r ps qs
      cis ← convertSubsts fl r is ks
      return $ CData d cps cis)
    (tcError "datatypes not convertible")

{-# COMPILE AGDA2HS convDatas #-}

convCons : Fuel → Rezz α →
           (@0 f g : Name)
           {@(tactic auto) p : f ∈ conScope}
           {@(tactic auto) q : g ∈ conScope}
           (lp : fieldScope f ⇒ α)
           (lq : fieldScope g ⇒ α)
         → TCM (Conv (TCon f lp) (TCon g lq))
convCons fl r f g {p} {q} lp lq = do
  ifDec (decIn p q)
    (λ where {{refl}} → do
      csp ← convertSubsts fl r lp lq
      return $ CCon f csp)
    (tcError "constructors not convertible")

{-# COMPILE AGDA2HS convCons #-}

convLams : Fuel
         → Rezz α
         → (@0 x y : Name)
           (u : Term (x ◃ α))
           (v : Term (y ◃ α))
         → TCM (Conv (TLam x u) (TLam y v))
convLams fl r x y u v = do
  CLam <$> convertCheck fl (rezzBind r) (renameTop r u) (renameTop r v)

{-# COMPILE AGDA2HS convLams #-}

convApps : Fuel
         → Rezz α
         → (u u' : Term α)
           (w w' : Term α)
         → TCM (Conv (TApp u w) (TApp u' w'))
convApps fl r u u' w w' = do
  cu ← convertCheck fl r u u'
  cw ← convertCheck fl r w w'
  return (CApp cu cw)

{-# COMPILE AGDA2HS convApps #-}

convertCase : Fuel
            → Rezz α
            → (u u' : Term α)
            → ∀ {@0 cs cs'} (ws : Branches α cs) (ws' : Branches α cs')
            → (rt : Type (x ◃ α)) (rt' : Type (y ◃ α))
            → TCM (Conv (TCase u ws rt) (TCase u' ws' rt'))
convertCase {x = x} fl r u u' ws ws' rt rt' = do
  cu ← convertCheck fl r u u'
  cm ← convertCheck fl (rezzBind {x = x} r)
                       (renameTop r (unType rt))
                       (renameTop r (unType rt'))
  Erased refl ← liftMaybe (allInScope (allBranches ws) (allBranches ws'))
    "comparing case statements with different branches"
  cbs ← convertBranches fl r ws ws'
  return (CCase ws ws' rt rt' cu cm cbs)

{-# COMPILE AGDA2HS convertCase #-}

convPis : Fuel
        → Rezz α
        → (@0 x y : Name)
          (u u' : Type α)
          (v  : Type (x ◃ α))
          (v' : Type (y ◃ α))
        → TCM (Conv (TPi x u v) (TPi y u' v'))
convPis fl r x y u u' v v' = do
  CPi <$> convertCheck fl r (unType u) (unType u')
      <*> convertCheck fl (rezzBind r) (unType v) (renameTop r (unType v'))

{-# COMPILE AGDA2HS convPis #-}

convertSubsts fl r SNil p = return CSNil
convertSubsts fl r (SCons x st) p =
  caseSubstBind p λ where
    y pt {{refl}} → do
      hc ← convertCheck fl r x y
      tc ← convertSubsts fl r st pt
      return (CSCons hc tc)

{-# COMPILE AGDA2HS convertSubsts #-}

convertBranch : Fuel
              → Rezz α
              → ∀ {@0 con : Name}
              → (b1 b2 : Branch α con)
              → TCM (ConvBranch b1 b2)
convertBranch fl r (BBranch _ {cp1} rz1 rhs1) (BBranch _ {cp2} rz2 rhs2) =
  ifDec (decIn cp1 cp2)
    (λ where {{refl}} → do
      CBBranch _ cp1 rz1 rz2 rhs1 rhs2 <$>
        convertCheck fl (rezzCong2 _<>_ (rezzCong revScope rz1) r) rhs1 rhs2)
    (tcError "can't convert two branches that match on different constructors")

{-# COMPILE AGDA2HS convertBranch #-}

convertBranches fl r BsNil        bp = return CBranchesNil
convertBranches fl r (BsCons bsh bst) bp =
  caseBsCons bp (λ where
    bph bpt {{refl}} → CBranchesCons <$> convertBranch fl r bsh bph <*> convertBranches fl r bst bpt)

{-# COMPILE AGDA2HS convertBranches #-}

convertWhnf : Fuel → Rezz α → (t q : Term α) → TCM (t ≅ q)
convertWhnf fl r (TVar x) (TVar y) = convVars x y
convertWhnf fl r (TDef x) (TDef y) = convDefs x y
convertWhnf fl r (TData d ps is) (TData e qs ks) = convDatas fl r d e ps qs is ks
convertWhnf fl r (TCon c lc) (TCon d ld) = convCons fl r c d lc ld
convertWhnf fl r (TLam x u) (TLam y v) = convLams fl r x y u v
convertWhnf fl r (TApp u e) (TApp v f) = convApps fl r u v e f
convertWhnf fl r (TProj u f) (TProj v g) = tcError "not implemented: conversion of projections"
convertWhnf fl r (TCase {cs = cs} u bs rt) (TCase {cs = cs'} u' bs' rt') =
  convertCase fl r u u' {cs} {cs'} bs bs' rt rt'
convertWhnf fl r (TPi x tu tv) (TPi y tw tz) = convPis fl r x y tu tw tv tz
convertWhnf fl r (TSort s) (TSort t) = convSorts s t
--let and ann shoudln't appear here since they get reduced away
convertWhnf fl r _ _ = tcError "two terms are not the same and aren't convertible"

{-# COMPILE AGDA2HS convertWhnf #-}

convertCheck None r t z =
  tcError "not enough fuel to check conversion"
convertCheck (More fl) r t q = do
  t ⟨ tred ⟩ ← reduceTo r t
  q ⟨ qred ⟩ ← reduceTo r q
  (CRedL tred ∘ CRedR qred) <$> convertWhnf fl r t q

{-# COMPILE AGDA2HS convertCheck #-}

convert : Rezz α → ∀ (t q : Term α) → TCM (t ≅ q)
convert r t q = do
  fl ← tcmFuel
  convertCheck fl r t q

{-# COMPILE AGDA2HS convert #-}
