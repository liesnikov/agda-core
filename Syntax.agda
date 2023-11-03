open import Utils
open Variables

import Scope

open import Data.Nat.Base

module Syntax 
    {Name     : Set} (let open Scope Name)
    (defs     : Scope)
    (cons     : Scope)
    (conArity : All (λ _ → Scope) cons) 
  where

data Term  (@0 α : Scope) : Set
data Sort  (@0 α : Scope) : Set
data Elim  (@0 α : Scope) : Set
data Elims (@0 α : Scope) : Set
data Branch (@0 α : Scope) : Set
data Branches (@0 α : Scope) : Set

-- Design choice: no separate syntactic class for types. Everything
-- is just a term or a sort.
Type = Term

data _⇒_ : (α β : Scope) → Set where
  []  : ∅ ⇒ β
  _∷_ : Term β → (α ⇒ β) → ((x ◃ α) ⇒ β)

-- This should ideally be the following:
--_⇒_ : (α β : Scope) → Set
--α ⇒ β = All (λ _ → Term β) α
-- but this would require a strict positivity annotation on All
-- TODO: is this because All is opaque?

data Term α where
  var    : (@0 x : Name) → {@(tactic auto) x∈α : x ∈ α} → Term α
  def    : (@0 d : Name) → {@(tactic auto) d∈defs : d ∈ defs} → Term α
  con    : (@0 c : Name) → {@(tactic auto) c∈cons : c ∈ cons} → ((conArity ! c) ⇒ α) → Term α
  lam    : (@0 x : Name) (v : Term (x ◃ α)) → Term α
  appE   : (u : Term α) (es : Elims α) → Term α
  pi     : (@0 x : Name) (a : Term α) (b : Term (x ◃ α)) → Term α
  sort   : Sort α → Term α
  let′   : (@0 x : Name) (u : Term α) (v : Term (x ◃ α)) → Term α
  -- TODO: literals
  -- TODO: constructor for type annotation

data Sort α where
  type : ℕ → Sort α -- TODO: universe polymorphism

data Elim α where
  arg  : Term α → Elim α
  proj : (x : Name) → {@(tactic auto) x∈defs : x ∈ defs} → Elim α
  case : (bs : Branches α) → Elim α
  -- TODO: do we need a type annotation for the return type of case?

data Elims α where
  []  : Elims α
  _∷_ : Elim α → Elims α → Elims α

_++E_ : Elims α → Elims α → Elims α
[]       ++E ys = ys
(x ∷ xs) ++E ys = x ∷ (xs ++E ys)

data Branch α where
  branch : (@0 c : Name) → {@(tactic auto) _ : c ∈ cons} → Term ((conArity ! c) <> α) → Branch α

data Branches α where
  []  : Branches α
  _∷_ : Branch α → Branches α → Branches α

apply : Term α → Term α → Term α
apply u v = appE u (arg v ∷ [])

elimView : Term α → Term α × Elims α
elimView (appE u es₂) = 
  let (u' , es₁) = elimView u
  in  u' , (es₁ ++E es₂)
elimView u = u , []

lookupEnv : α ⇒ β → (@0 x : Name) → {@(tactic auto) _ : x ∈ α} → Term β
lookupEnv [] x {q} = ∅-case q
lookupEnv (u ∷ f) x {q} = ◃-case q (λ _ → u) (λ r → lookupEnv f x)

weaken : α ⊆ β → Term α → Term β
weakenSort : α ⊆ β → Sort α → Sort β
weakenElim : α ⊆ β → Elim α → Elim β
weakenElims : α ⊆ β → Elims α → Elims β
weakenBranch : α ⊆ β → Branch α → Branch β
weakenBranches : α ⊆ β → Branches α → Branches β
weakenEnv : β ⊆ γ → α ⇒ β → α ⇒ γ

weaken p (var x {q})      = var x {coerce p q}
weaken p (def f)          = def f
weaken p (con c vs)       = con c (weakenEnv p vs)
weaken p (lam x v)        = lam x (weaken (⊆-◃-keep p) v)
weaken p (appE u es)      = appE (weaken p u) (weakenElims p es)
weaken p (pi x a b)       = pi x (weaken p a) (weaken (⊆-◃-keep p) b)
weaken p (sort α)         = sort (weakenSort p α)
weaken p (let′ x v t)     = let′ x (weaken p v) (weaken (⊆-◃-keep p) t)

weakenSort p (type x) = type x

weakenElim p (arg x)   = arg (weaken p x)
weakenElim p (proj x)  = proj x
weakenElim p (case bs) = case (weakenBranches p bs)

weakenElims p []       = []
weakenElims p (e ∷ es) = weakenElim p e ∷ weakenElims p es

weakenBranch p (branch c x) = branch c (weaken (⊆-<>-keep p) x)

weakenBranches p []       = []
weakenBranches p (b ∷ bs) = weakenBranch p b ∷ weakenBranches p bs

weakenEnv p [] = []
weakenEnv p (u ∷ e) = weaken p u ∷ weakenEnv p e

opaque
  unfolding Scope.Scope Scope._⊆_

  idEnv : {{Rezz β}} → β ⇒ β
  idEnv {{rezz []}}    = []
  idEnv {{rezz (x ∷ β)}} = var (get x) {here} ∷ weakenEnv (⊆-◃-drop ⊆-refl) idEnv

  liftEnv : {{Rezz α}} → β ⇒ γ → (α <> β) ⇒ (α <> γ)
  liftEnv {{rezz []}} e = e
  liftEnv {{rezz (x ∷ α)}} e = var (get x) {here} ∷ weakenEnv (⊆-◃-drop ⊆-refl) (liftEnv e)

  coerceEnv : {{Rezz α}} → α ⊆ β → β ⇒ γ → α ⇒ γ
  coerceEnv {{rezz []}} p e = []
  coerceEnv {{rezz (x ∷ α)}} p e = lookupEnv e _ {◃-⊆-to-∈ p} ∷ coerceEnv (<>-⊆-right p) e

  dropEnv : (x ◃ α) ⇒ β → α ⇒ β
  dropEnv (x ∷ f) = f

raiseEnv : {{Rezz β}} → α ⇒ β → (α <> β) ⇒ β
raiseEnv {{r}} []      = subst (_⇒ _) (sym ∅-<>) (idEnv {{r}})
raiseEnv {{r}} (u ∷ e) = subst (_⇒ _) (sym <>-assoc) (u ∷ raiseEnv {{r}} e)

raise : {{Rezz α}} → Term β → Term (α <> β)
raise {{r}} = weaken (⊆-right (⋈-refl {{r}}))

-- -}
