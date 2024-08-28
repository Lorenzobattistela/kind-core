module Kind.Equal where

import Control.Monad (zipWithM)

import Kind.Env
import Kind.Reduce
import Kind.Type
import Kind.Util

import qualified Data.Map.Strict as M
import qualified Data.IntMap.Strict as IM
import Debug.Trace

-- Equality
-- --------

-- Checks if two terms are equal, after reduction steps
equal :: Term -> Term -> Int -> Env Bool
equal a b dep = {-trace ("== " ++ termShow a dep ++ "\n.. " ++ termShow b dep) $-} do
  -- Reduces both sides to wnf
  book <- envGetBook
  fill <- envGetFill
  let a' = reduce book fill 2 a
  let b' = reduce book fill 2 b
  state <- envSnapshot
  -- If both sides are identical, return true
  is_id <- identical a' b' dep
  if is_id then
    envPure True
  -- Otherwise, check if they're component-wise equal
  else do
    envRewind state
    similar a' b' dep

-- Checks if two terms are already syntactically identical
identical :: Term -> Term -> Int -> Env Bool
identical a b dep = go a b dep where
  go (All aNam aInp aBod) (All bNam bInp bBod) dep = do
    iInp <- identical aInp bInp dep
    iBod <- identical (aBod (Var aNam dep)) (bBod (Var bNam dep)) (dep + 1)
    return (iInp && iBod)
  go (Lam aNam aBod) (Lam bNam bBod) dep =
    identical (aBod (Var aNam dep)) (bBod (Var bNam dep)) (dep + 1)
  go (App aFun aArg) (App bFun bArg) dep = do
    iFun <- identical aFun bFun dep
    iArg <- identical aArg bArg dep
    return (iFun && iArg)
  go (Slf aNam aTyp aBod) (Slf bNam bTyp bBod) dep =
    identical aTyp bTyp dep
  go (Ins aVal) b dep =
    identical aVal b dep
  go a (Ins bVal) dep =
    identical a bVal dep
  go (Dat aScp aCts) (Dat bScp bCts) dep = do
    iSlf <- zipWithM (\ax bx -> identical ax bx dep) aScp bScp
    if and iSlf && length aCts == length bCts
      then and <$> zipWithM goCtr aCts bCts
      else return False
  go (Con aNam aArg) (Con bNam bArg) dep = do
    if aNam == bNam && length aArg == length bArg
      then and <$> zipWithM (\aArg bArg -> identical aArg bArg dep) aArg bArg
      else return False
  go (Mat aCse) (Mat bCse) dep = do
    if length aCse == length bCse
      then and <$> zipWithM goCse aCse bCse
      else return False
  go (Let aNam aVal aBod) b dep =
    identical (aBod aVal) b dep
  go a (Let bNam bVal bBod) dep =
    identical a (bBod bVal) dep
  go (Use aNam aVal aBod) b dep =
    identical (aBod aVal) b dep
  go a (Use bNam bVal bBod) dep =
    identical a (bBod bVal) dep
  go Set Set dep =
    return True
  go (Ann chk aVal aTyp) b dep =
    identical aVal b dep
  go a (Ann chk bVal bTyp) dep =
    identical a bVal dep
  go a (Met bUid bSpn) dep =
    unify bUid bSpn a dep
  go (Met aUid aSpn) b dep =
    unify aUid aSpn b dep
  go (Hol aNam aCtx) b dep =
    return True
  go a (Hol bNam bCtx) dep =
    return True
  go U32 U32 dep =
    return True
  go (Num aVal) (Num bVal) dep =
    return (aVal == bVal)
  go (Op2 aOpr aFst aSnd) (Op2 bOpr bFst bSnd) dep = do
    iFst <- identical aFst bFst dep
    iSnd <- identical aSnd bSnd dep
    return (iFst && iSnd)
  go (Swi aNam aX aZ aS aP) (Swi bNam bX bZ bS bP) dep = do
    iX <- identical aX bX dep
    iZ <- identical aZ bZ dep
    iS <- identical (aS (Var (aNam ++ "-1") dep)) (bS (Var (bNam ++ "-1") dep)) dep
    iP <- identical (aP (Var aNam dep)) (bP (Var bNam dep)) dep
    return (iX && iZ && iS && iP)
  go (Txt aTxt) (Txt bTxt) dep =
    return (aTxt == bTxt)
  go (Nat aVal) (Nat bVal) dep =
    return (aVal == bVal)
  go (Src aSrc aVal) b dep =
    identical aVal b dep
  go a (Src bSrc bVal) dep =
    identical a bVal dep
  go (Ref aNam) (Ref bNam) dep =
    return (aNam == bNam)
  go (Var aNam aIdx) (Var bNam bIdx) dep =
    return (aIdx == bIdx)
  go a b dep =
    return False

  goCtr (Ctr aCNm aFs aRt) (Ctr bCNm bFs bRt) = do
    if aCNm == bCNm && length aFs == length bFs
      then do
        fs <- zipWithM (\(_, aFTy) (_, bFTy) -> identical aFTy bFTy dep) aFs bFs
        rt <- identical aRt bRt dep
        return (and fs && rt)
      else return False

  goCse (aCNam, aCBod) (bCNam, bCBod) = do
    if aCNam == bCNam
      then identical aCBod bCBod dep
      else return False

-- Checks if two terms are component-wise equal
similar :: Term -> Term -> Int -> Env Bool
similar a b dep = go a b dep where
  go (All aNam aInp aBod) (All bNam bInp bBod) dep = do
    eInp <- equal aInp bInp dep
    eBod <- equal (aBod (Var aNam dep)) (bBod (Var bNam dep)) (dep + 1)
    return (eInp && eBod)
  go (Lam aNam aBod) (Lam bNam bBod) dep =
    equal (aBod (Var aNam dep)) (bBod (Var bNam dep)) (dep + 1)
  go (App aFun aArg) (App bFun bArg) dep = do
    eFun <- similar aFun bFun dep
    eArg <- equal aArg bArg dep
    return (eFun && eArg)
  go (Slf aNam aTyp aBod) (Slf bNam bTyp bBod) dep = do
    book <- envGetBook
    similar (reduce book IM.empty 0 aTyp) (reduce book IM.empty 0 bTyp) dep
  go (Dat aScp aCts) (Dat bScp bCts) dep = do
    eSlf <- zipWithM (\ax bx -> equal ax bx dep) aScp bScp
    if and eSlf && length aCts == length bCts
      then and <$> zipWithM goCtr aCts bCts
      else return False
  go (Con aNam aArg) (Con bNam bArg) dep = do
    if aNam == bNam && length aArg == length bArg
      then and <$> zipWithM (\a b -> equal a b dep) aArg bArg
      else return False
  go (Mat aCse) (Mat bCse) dep = do
    if length aCse == length bCse
      then and <$> zipWithM goCse aCse bCse
      else return False
  go (Op2 aOpr aFst aSnd) (Op2 bOpr bFst bSnd) dep = do
    eFst <- equal aFst bFst dep
    eSnd <- equal aSnd bSnd dep
    return (eFst && eSnd)
  go (Swi aNam aX aZ aS aP) (Swi bNam bX bZ bS bP) dep = do
    eX <- equal aX bX dep
    eZ <- equal aZ bZ dep
    eS <- equal (aS (Var (aNam ++ "-1") dep)) (bS (Var (bNam ++ "-1") dep)) dep
    eP <- equal (aP (Var aNam dep)) (bP (Var bNam dep)) dep
    return (eX && eZ && eS && eP)
  go a b dep = identical a b dep

  goCtr (Ctr aCNm aFs aRt) (Ctr bCNm bFs bRt) = do
    if aCNm == bCNm && length aFs == length bFs
      then do
        fs <- zipWithM (\(_, aFTyp) (_, bFTyp) -> equal aFTyp bFTyp dep) aFs bFs
        rt <- equal aRt bRt dep
        return (and fs && rt)
      else return False

  goCse (aCNam, aCBod) (bCNam, bCBod) = do
    if aCNam == bCNam
      then equal aCBod bCBod dep
      else return False

-- Unification
-- -----------

-- The unification algorithm is a simple pattern unifier, based on smalltt:
-- > https://github.com/AndrasKovacs/elaboration-zoo/blob/master/03-holes/Main.hs
-- The pattern unification problem provides a solution to the following problem:
--   (?X x y z ...) = K
-- When:
--   1. The LHS spine, `x y z ...`, consists of distinct variables.
--   2. Every free var of the RHS, `K`, occurs in the spine.
--   3. The LHS hole, `?A`, doesn't occur in the RHS, `K`.
-- If these conditions are met, ?X is solved as:
--   ?X = λx λy λz ... K
-- In this implementation, checking condition `2` is not necessary, because we
-- subst holes directly where they occur (rather than on top-level definitions),
-- so, it is impossible for unbound variables to appear. This approach may not
-- be completely correct, and is pending review.

-- If possible, solves a `(?X x y z ...) = K` problem, generating a subst.
unify :: Int -> [Term] -> Term -> Int -> Env Bool
unify uid spn b dep = do
  book <- envGetBook
  fill <- envGetFill

  -- is this hole not already solved?
  let unsolved = not (IM.member uid fill)

  -- does the spine satisfies conditions?
  let solvable = valid fill spn []

  -- is the solution not recursive?
  let no_loops = not $ occur book fill uid b dep

  -- trace ("unify: " ++ show uid ++ " " ++ termShow b dep ++ " | " ++ show unsolved ++ " " ++ show solvable ++ " " ++ show no_loops) $ do
  do

    -- If all is ok, generate the solution and return true
    if unsolved && solvable && no_loops then do
      let solution = solve book fill uid spn b
      envFill uid solution
      return True

    -- Otherwise, return true iff both are identical metavars
    else case b of
      (Met bUid bSpn) -> return $ uid == bUid
      other           -> return False

-- Checks if a problem is solveable by pattern unification.
valid :: Fill -> [Term] -> [Int] -> Bool
valid fill []        vars = True
valid fill (x : spn) vars = case reduce M.empty fill 0 x of
  (Var nam idx) -> not (elem idx vars) && valid fill spn (idx : vars)
  otherwise     -> False

-- Generates the solution, adding binders and renaming variables.
solve :: Book -> Fill -> Int -> [Term] -> Term -> Term
solve book fill uid []        b = b
solve book fill uid (x : spn) b = case reduce book fill 0 x of
  (Var nam idx) -> Lam nam $ \x -> subst idx x (solve book fill uid spn b)
  otherwise     -> error "unreachable"
