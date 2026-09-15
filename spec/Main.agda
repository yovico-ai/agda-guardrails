-- Executable IO boundary only — same discipline as Yovico's real
-- OracleMain.agda: no parsing or policy logic lives here, both stay in
-- Oracle.agda so they type-check under --safe. This does simplify that
-- file's actual protocol, which is deliberate and explained in the
-- README: the real oracle reads a length-prefixed batch and answers with
-- one combined line, built for a Node host driving fuzz campaigns; this
-- demo's Go client instead keeps ONE compiled process alive for an entire
-- property-test run and sends one query per line, so the boundary here is
-- just "read a line, answer a line, forever" — no batching, no framing.
-- The client shuts the process down by killing it, not by closing stdin,
-- so this loop never needs to detect end-of-input.
{-# OPTIONS --guardedness #-}
module Main where

open import Data.Unit.Polymorphic.Base using (⊤)
import Data.Unit.Base as Unit0 using (⊤)
open import IO using (IO; Main; run; forever; lift′; _>>_; _>>=_)
import IO.Primitive.Core as Prim using (IO)
open import IO.Finite using (getLine; putStrLn)
open import Level using (0ℓ)
open import Oracle using (evaluate)

-- GHC block-buffers stdout by default whenever it isn't a terminal — true
-- of the pipe harness/oracle_client.go talks over — so a one-line
-- response sits in an internal buffer instead of reaching Go, and the
-- whole request/response protocol hangs forever on the very first query.
-- IO.Finite has no buffering control, so this reaches straight past it to
-- the one Haskell call that fixes it.
postulate
  primSetLineBuffering : Prim.IO Unit0.⊤

{-# FOREIGN GHC import System.IO #-}
{-# COMPILE GHC primSetLineBuffering = System.IO.hSetBuffering System.IO.stdout System.IO.LineBuffering #-}

setLineBuffering : IO {0ℓ} ⊤
setLineBuffering = lift′ primSetLineBuffering

respondOnce : IO {0ℓ} ⊤
respondOnce = getLine >>= λ line → putStrLn (evaluate line)

main : Main
main = run (setLineBuffering >> forever respondOnce)
