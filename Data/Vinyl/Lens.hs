{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE ConstraintKinds       #-}
{-# LANGUAGE DataKinds             #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE FlexibleInstances     #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds             #-}
{-# LANGUAGE ScopedTypeVariables   #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE TypeOperators         #-}
-- | Lenses into record fields.
module Data.Vinyl.Lens
  ( RecElem(..)
  , rget, rput, rput', rlens, rlens'
  , RElem
  , RecSubset(..)
  , RSubset
  , REquivalent
  , type (∈)
  , type (⊆)
  , type (≅)
  , type (<:)
  , type (:~:)
  ) where

import Data.Kind (Constraint)
import Data.Vinyl.Core
import Data.Vinyl.Functor
import Data.Vinyl.TypeLevel

-- | The presence of a field in a record is witnessed by a lens into its value.
-- The third parameter to 'RElem', @i@, is there to help the constraint solver
-- realize that this is a decidable predicate with respect to the judgemental
-- equality in @k@.
class i ~ RIndex r rs => RecElem record (r :: k) (r' :: k)
                                        (rs :: [k]) (rs' :: [k])
                                        (i :: Nat) | r r' rs i -> rs' where
  -- | An opportunity for instances to generate constraints based on
  -- the functor parameter of records passed to class methods.
  type RecElemFCtx record (f :: k -> *) :: Constraint
  type RecElemFCtx record f = ()

  -- | We can get a lens for getting and setting the value of a field which is
  -- in a record. As a convenience, we take a proxy argument to fix the
  -- particular field being viewed. These lenses are compatible with the @lens@
  -- library. Morally:
  --
  -- > rlensC :: Lens' (Rec f rs) (Rec f rs') (f r) (f r')
  rlensC
    :: (Functor g, RecElemFCtx record f)
    => (f r -> g (f r'))
    -> record f rs
    -> g (record f rs')

  -- | For Vinyl users who are not using the @lens@ package, we provide a getter.
  rgetC
    :: (RecElemFCtx record f, r ~ r')
    => record f rs
    -> f r

  -- | For Vinyl users who are not using the @lens@ package, we also provide a
  -- setter. In general, it will be unambiguous what field is being written to,
  -- and so we do not take a proxy argument here.
  rputC
    :: RecElemFCtx record f
    => f r'
    -> record f rs
    -> record f rs'

-- | 'RecElem' for classic vinyl 'Rec' types.
type RElem = RecElem Rec

-- This is an internal convenience stolen from the @lens@ library.
lens
  :: Functor f
  => (s -> a)
  -> (s -> b -> t)
  -> (a -> f b)
  -> s
  -> f t
lens sa sbt afb s = fmap (sbt s) $ afb (sa s)
{-# INLINE lens #-}

instance RecElem Rec r r' (r ': rs) (r' ': rs) 'Z where
  rlensC f (x :& xs) = fmap (:& xs) (f x)
  {-# INLINE rlensC #-}
  rgetC = getConst . rlensC Const
  {-# INLINE rgetC #-}
  rputC y = getIdentity . rlensC @_ @r (\_ -> Identity y)
  {-# INLINE rputC #-}

instance (RIndex r (s ': rs) ~ 'S i, RElem r r' rs rs' i)
  => RecElem Rec r r' (s ': rs) (s ': rs') ('S i) where
  rlensC f (x :& xs) = fmap (x :&) (rlensC f xs)
  {-# INLINE rlensC #-}
  rgetC = getConst . rlensC @_ @r @r' Const
  {-# INLINE rgetC #-}
  rputC y = getIdentity . rlensC @_ @r (\_ -> Identity y)
  {-# INLINE rputC #-}

--  | The 'rgetC' field getter with the type arguments re-ordered for
--  more convenient usage with @TypeApplications@.
rget :: forall r rs f record.
        (RecElem record r r rs rs (RIndex r rs), RecElemFCtx record f)
     => record f rs -> f r
rget = rgetC

-- | The type-changing field setter 'rputC' with the type arguments
-- re-ordered for more convenient usage with @TypeApplicatiosn@.
rput' :: forall r r' rs rs' record f. (RecElem record r r' rs rs' (RIndex r rs), RecElemFCtx record f)
      => f r' -> record f rs -> record f rs'
rput' = rputC @_ @r @r'

-- | Type-preserving field setter. This type is simpler to work with
-- than that of 'rput''.
rput :: forall r rs record f. (RecElem record r r rs rs (RIndex r rs), RecElemFCtx record f)
      => f r -> record f rs -> record f rs
rput = rput' @r

-- | Type-changing field lens 'rlensC' with the type arguments
-- re-ordered for more convenient usage with @TypeApplications@.
rlens' :: forall r r' record rs rs' f g.
          (RecElem record r r' rs rs' (RIndex r rs), RecElemFCtx record f, Functor g)
       => (f r -> g (f r')) -> record f rs -> g (record f rs')
rlens' = rlensC

-- | Type-preserving field lens. This type is simpler to work with
-- than that of 'rlens''.
rlens :: forall r record rs f g.
         (RecElem record r r rs rs (RIndex r rs), RecElemFCtx record f, Functor g)
       => (f r -> g (f r)) -> record f rs -> g (record f rs)
rlens = rlensC

-- | If one field set is a subset another, then a lens of from the latter's
-- record to the former's is evident. That is, we can either cast a larger
-- record to a smaller one, or we may replace the values in a slice of a
-- record.
class is ~ RImage rs ss => RecSubset record (rs :: [k]) (ss :: [k]) is where
  -- | An opportunity for instances to generate constraints based on
  -- the functor parameter of records passed to class methods.
  type RecSubsetFCtx record (f :: k -> *) :: Constraint
  type RecSubsetFCtx record f = ()

  -- | This is a lens into a slice of the larger record. Morally, we have:
  --
  -- > rsubset :: Lens' (Rec f ss) (Rec f rs)
  rsubset
    :: (Functor g, RecSubsetFCtx record f)
    => (record f rs -> g (record f rs))
    -> record f ss
    -> g (record f ss)

  -- | The getter of the 'rsubset' lens is 'rcast', which takes a larger record
  -- to a smaller one by forgetting fields.
  rcast
    :: RecSubsetFCtx record f
    => record f ss
    -> record f rs
  rcast = getConst . rsubset Const
  {-# INLINE rcast #-}

  -- | The setter of the 'rsubset' lens is 'rreplace', which allows a slice of
  -- a record to be replaced with different values.
  rreplace
    :: RecSubsetFCtx record f
    => record f rs
    -> record f ss
    -> record f ss
  rreplace rs = getIdentity . rsubset (\_ -> Identity rs)
  {-# INLINE rreplace #-}

type RSubset = RecSubset Rec

instance RecSubset Rec '[] ss '[] where
  rsubset = lens (const RNil) const

instance (RElem r r ss ss i , RSubset rs ss is) => RecSubset Rec (r ': rs) ss (i ': is) where
  rsubset = lens (\ss -> rget ss :& rcast ss) set
    where
      set :: Rec f ss -> Rec f (r ': rs) -> Rec f ss
      set ss (r :& rs) = rput r $ rreplace rs ss

-- | Two record types are equivalent when they are subtypes of each other.
type REquivalent rs ss is js = (RSubset rs ss is, RSubset ss rs js)

-- | A shorthand for 'RElem' which supplies its index.
type r ∈ rs = RElem r r rs rs (RIndex r rs)

-- | A shorthand for 'RSubset' which supplies its image.
type rs ⊆ ss = RSubset rs ss (RImage rs ss)

-- | A shorthand for 'REquivalent' which supplies its images.
type rs ≅ ss = REquivalent rs ss (RImage rs ss) (RImage ss rs)

-- | A non-unicode equivalent of @(⊆)@.
type rs <: ss = rs ⊆ ss

-- | A non-unicode equivalent of @(≅)@.
type rs :~: ss = rs ≅ ss
