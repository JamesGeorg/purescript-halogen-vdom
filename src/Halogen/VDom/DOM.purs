module Halogen.VDom.DOM
  ( VDomSpec(..)
  , buildVDom
  , buildText
  , buildElem
  , buildKeyed
  ) where

import Prelude

import Data.Array as Array
import Data.Function.Uncurried as Fn
import Data.Maybe (Maybe(..))
import Data.Nullable (toNullable)
import Data.Tuple (Tuple(..), fst)
import Effect.Uncurried as EFn
import Foreign.Object as Object
import Halogen.VDom.Machine (Machine, Step, Step'(..), extract, halt, mkStep, step)
import Halogen.VDom.Machine as Machine
import Halogen.VDom.Types (ElemName(..), Namespace(..), VDom(..))
import Halogen.VDom.Util as Util
import Web.DOM.Document (Document) as DOM
import Web.DOM.Element (Element) as DOM
import Web.DOM.Element as DOMElement
import Web.DOM.Node (Node) as DOM

type VDomMachine a = Machine (VDom a) DOM.Node

type VDomStep a = Step (VDom a) DOM.Node

type VDomInit i a = EFn.EffectFn1 i (VDomStep a)

type VDomBuilder i a w = EFn.EffectFn3 (VDomSpec a) (VDomMachine a) i (VDomStep a)

type VDomBuilder4 i j k l a w = EFn.EffectFn6 (VDomSpec a) (VDomMachine a) i j k l (VDomStep a)

-- | Widget machines recursively reference the configured spec to potentially
-- | enable recursive trees of Widgets.
newtype VDomSpec a = VDomSpec
  { buildAttributes ∷ DOM.Element → Machine a Unit
  , document ∷ DOM.Document
  }

-- | Starts an initial `VDom` machine by providing a `VDomSpec`.
-- |
-- | ```purescript
-- | main = do
-- |   machine1 ← buildVDom spec vdomTree1
-- |   machine2 ← Machine.step machine1 vdomTree2
-- |   machine3 ← Machine.step machine2 vdomTree3
-- |   ...
-- | ````
buildVDom ∷ ∀ a. VDomSpec a → VDomMachine a
buildVDom spec = build
  where
  build = EFn.mkEffectFn1 case _ of
    Text s → EFn.runEffectFn3 buildText spec build s
    Elem ns n a ch → EFn.runEffectFn6 buildElem spec build ns n a ch
    Keyed ns n a ch → EFn.runEffectFn6 buildKeyed spec build ns n a ch

type TextState a w =
  { build ∷ VDomMachine a
  , node ∷ DOM.Node
  , value ∷ String
  }

buildText ∷ ∀ a w. VDomBuilder String a w
buildText = EFn.mkEffectFn3 \(VDomSpec spec) build s → do
  node ← EFn.runEffectFn2 Util.createTextNode s spec.document
  let state = { build, node, value: s }
  pure $ mkStep $ Step node state patchText haltText

patchText ∷ ∀ a w. EFn.EffectFn2 (TextState a w) (VDom a) (VDomStep a)
patchText = EFn.mkEffectFn2 \state vdom → do
  let { build, node, value: value1 } = state
  case vdom of
    Text value2
      | value1 == value2 →
          pure $ mkStep $ Step node state patchText haltText
      | otherwise → do
          let nextState = { build, node, value: value2 }
          EFn.runEffectFn2 Util.setTextContent value2 node
          pure $ mkStep $ Step node nextState patchText haltText
    _ → do
      EFn.runEffectFn1 haltText state
      EFn.runEffectFn1 build vdom

haltText ∷ ∀ a w. EFn.EffectFn1 (TextState a w) Unit
haltText = EFn.mkEffectFn1 \{ node } → do
  parent ← EFn.runEffectFn1 Util.parentNode node
  EFn.runEffectFn2 Util.removeChild node parent

type ElemState a =
  { build ∷ VDomMachine a
  , node ∷ DOM.Node
  , attrs ∷ Step a Unit
  , ns ∷ Maybe Namespace
  , name ∷ ElemName
  , children ∷ Array (VDomStep a)
  }

buildElem ∷ ∀ a w. VDomBuilder4 (Maybe Namespace) ElemName a (Array (VDom a)) a w
buildElem = EFn.mkEffectFn6 \(VDomSpec spec) build ns1 name1 as1 ch1 → do
  el ← EFn.runEffectFn3 Util.createElement (toNullable ns1) name1 spec.document
  let
    node = DOMElement.toNode el
    onChild = EFn.mkEffectFn2 \ix child → do
      res ← EFn.runEffectFn1 build child
      EFn.runEffectFn3 Util.insertChildIx ix (extract res) node
      pure res
  children ← EFn.runEffectFn2 Util.forE ch1 onChild
  attrs ← EFn.runEffectFn1 (spec.buildAttributes el) as1
  let
    state =
      { build
      , node
      , attrs
      , ns: ns1
      , name: name1
      , children
      }
  pure $ mkStep $ Step node state patchElem haltElem

patchElem ∷ ∀ a w. EFn.EffectFn2 (ElemState a) (VDom a) (VDomStep a)
patchElem = EFn.mkEffectFn2 \state vdom → do
  let { build, node, attrs, ns: ns1, name: name1, children: ch1 } = state
  case vdom of
    Elem ns2 name2 as2 ch2 | Fn.runFn4 eqElemSpec ns1 name1 ns2 name2 → do
      case Array.length ch1, Array.length ch2 of
        0, 0 → do
          attrs2 ← EFn.runEffectFn2 step attrs as2
          let
            nextState =
              { build
              , node
              , attrs: attrs2
              , ns: ns2
              , name: name2
              , children: ch1
              }
          pure $ mkStep $ Step node nextState patchElem haltElem
        _, _ → do
          let
            onThese = EFn.mkEffectFn3 \ix s v → do
              res ← EFn.runEffectFn2 step s v
              EFn.runEffectFn3 Util.insertChildIx ix (extract res) node
              pure res
            onThis = EFn.mkEffectFn2 \ix s → EFn.runEffectFn1 halt s
            onThat = EFn.mkEffectFn2 \ix v → do
              res ← EFn.runEffectFn1 build v
              EFn.runEffectFn3 Util.insertChildIx ix (extract res) node
              pure res
          children2 ← EFn.runEffectFn5 Util.diffWithIxE ch1 ch2 onThese onThis onThat
          attrs2 ← EFn.runEffectFn2 step attrs as2
          let
            nextState =
              { build
              , node
              , attrs: attrs2
              , ns: ns2
              , name: name2
              , children: children2
              }
          pure $ mkStep $ Step node nextState patchElem haltElem
    _ → do
      EFn.runEffectFn1 haltElem state
      EFn.runEffectFn1 build vdom

haltElem ∷ ∀ a w. EFn.EffectFn1 (ElemState a) Unit
haltElem = EFn.mkEffectFn1 \{ node, attrs, children } → do
  parent ← EFn.runEffectFn1 Util.parentNode node
  EFn.runEffectFn2 Util.removeChild node parent
  EFn.runEffectFn2 Util.forEachE children halt
  EFn.runEffectFn1 halt attrs

type KeyedState a w =
  { build ∷ VDomMachine a
  , node ∷ DOM.Node
  , attrs ∷ Step a Unit
  , ns ∷ Maybe Namespace
  , name ∷ ElemName
  , children ∷ Object.Object (VDomStep a)
  , length ∷ Int
  }

buildKeyed ∷ ∀ a w. VDomBuilder4 (Maybe Namespace) ElemName a (Array (Tuple String (VDom a))) a w
buildKeyed = EFn.mkEffectFn6 \(VDomSpec spec) build ns1 name1 as1 ch1 → do
  el ← EFn.runEffectFn3 Util.createElement (toNullable ns1) name1 spec.document
  let
    node = DOMElement.toNode el
    onChild = EFn.mkEffectFn3 \k ix (Tuple _ vdom) → do
      res ← EFn.runEffectFn1 build vdom
      EFn.runEffectFn3 Util.insertChildIx ix (extract res) node
      pure res
  children ← EFn.runEffectFn3 Util.strMapWithIxE ch1 fst onChild
  attrs ← EFn.runEffectFn1 (spec.buildAttributes el) as1
  let
    state =
      { build
      , node
      , attrs
      , ns: ns1
      , name: name1
      , children
      , length: Array.length ch1
      }
  pure $ mkStep $ Step node state patchKeyed haltKeyed

patchKeyed ∷ ∀ a w. EFn.EffectFn2 (KeyedState a w) (VDom a) (VDomStep a)
patchKeyed = EFn.mkEffectFn2 \state vdom → do
  let { build, node, attrs, ns: ns1, name: name1, children: ch1, length: len1 } = state
  case vdom of
    Keyed ns2 name2 as2 ch2 | Fn.runFn4 eqElemSpec ns1 name1 ns2 name2 →
      case len1, Array.length ch2 of
        0, 0 → do
          attrs2 ← EFn.runEffectFn2 Machine.step attrs as2
          let
            nextState =
              { build
              , node
              , attrs: attrs2
              , ns: ns2
              , name: name2
              , children: ch1
              , length: 0
              }
          pure $ mkStep $ Step node nextState patchKeyed haltKeyed
        _, len2 → do
          let
            onThese = EFn.mkEffectFn4 \_ ix' s (Tuple _ v) → do
              res ← EFn.runEffectFn2 step s v
              EFn.runEffectFn3 Util.insertChildIx ix' (extract res) node
              pure res
            onThis = EFn.mkEffectFn2 \_ s → EFn.runEffectFn1 halt s
            onThat = EFn.mkEffectFn3 \_ ix (Tuple _ v) → do
              res ← EFn.runEffectFn1 build v
              EFn.runEffectFn3 Util.insertChildIx ix (extract res) node
              pure res
          children2 ← EFn.runEffectFn6 Util.diffWithKeyAndIxE ch1 ch2 fst onThese onThis onThat
          attrs2 ← EFn.runEffectFn2 step attrs as2
          let
            nextState =
              { build
              , node
              , attrs: attrs2
              , ns: ns2
              , name: name2
              , children: children2
              , length: len2
              }
          pure $ mkStep $ Step node nextState patchKeyed haltKeyed
    _ → do
      EFn.runEffectFn1 haltKeyed state
      EFn.runEffectFn1 build vdom

haltKeyed ∷ ∀ a w. EFn.EffectFn1 (KeyedState a w) Unit
haltKeyed = EFn.mkEffectFn1 \{ node, attrs, children } → do
  parent ← EFn.runEffectFn1 Util.parentNode node
  EFn.runEffectFn2 Util.removeChild node parent
  EFn.runEffectFn2 Util.forInE children (EFn.mkEffectFn2 \_ s → EFn.runEffectFn1 halt s)
  EFn.runEffectFn1 halt attrs

eqElemSpec ∷ Fn.Fn4 (Maybe Namespace) ElemName (Maybe Namespace) ElemName Boolean
eqElemSpec = Fn.mkFn4 \ns1 (ElemName name1) ns2 (ElemName name2) →
  if name1 == name2
    then case ns1, ns2 of
      Just (Namespace ns1'), Just (Namespace ns2') | ns1' == ns2' → true
      Nothing, Nothing → true
      _, _ → false
    else false
