module Halogen.VDom.Types
  ( VDom(..)
  , ElemName(..)
  , Namespace(..)
  ) where

import Prelude
import Data.Maybe (Maybe)
import Data.Newtype (class Newtype)
import Data.Tuple (Tuple)

-- | The core virtual-dom tree type, where `a` is the type of attributes,
-- | and `w` is the type of "widgets". Widgets are machines that have complete
-- | control over the lifecycle of some `DOM.Node`.
-- |
-- | The `Grafted` constructor and associated machinery enables `bimap`
-- | fusion using a Coyoneda-like encoding.
data VDom a
  = Text String
  | Elem (Maybe Namespace) ElemName a (Array (VDom a))
  | Keyed (Maybe Namespace) ElemName a (Array (Tuple String (VDom a)))

newtype ElemName = ElemName String

derive instance newtypeElemName ∷ Newtype ElemName _
derive newtype instance eqElemName ∷ Eq ElemName
derive newtype instance ordElemName ∷ Ord ElemName

newtype Namespace = Namespace String

derive instance newtypeNamespace ∷ Newtype Namespace _
derive newtype instance eqNamespace ∷ Eq Namespace
derive newtype instance ordNamespace ∷ Ord Namespace
