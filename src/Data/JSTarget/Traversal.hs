{-# LANGUAGE FlexibleInstances, TupleSections, PatternGuards #-}
-- | Generic traversal of JSTarget AST types.
module Data.JSTarget.Traversal where
import Control.Applicative
import Control.Monad
import Control.Monad.Identity
import Data.JSTarget.AST

-- | AST nodes we'd like to fold and map over.
data ASTNode = Exp !Exp !Bool | Stm !Stm !Bool | Shared !Stm

type TravM a = Identity a

runTravM :: TravM a -> a
runTravM = runIdentity

class Show ast => JSTrav ast where
  -- | Bottom up transform over an AST.
  foldMapJS :: (a -> ASTNode -> Bool)       -- ^ Enter node?
            -> (a -> Exp -> TravM (a, Exp)) -- ^ Exp to Exp mapping.
            -> (a -> Stm -> TravM (a, Stm)) -- ^ Stm to Stm mapping.
            -> a                            -- ^ Starting accumulator.
            -> ast                          -- ^ AST to map over.
            -> TravM (a, ast)

  -- | Bottom up fold of an AST.
  foldJS :: (a -> ASTNode -> Bool)    -- ^ Should the given node be entered?
                                      --   The step function is always applied
                                      --   to the current node, however.
         -> (a -> ASTNode -> TravM a) -- ^ Step function.
         -> a                         -- ^ Initial value.
         -> ast                       -- ^ AST to fold over.
         -> TravM a

mapJS :: JSTrav ast
      => (ASTNode -> Bool)
      -> (Exp -> TravM Exp)
      -> (Stm -> TravM Stm)
      -> ast
      -> TravM ast
mapJS tr fe fs ast =
    snd <$> foldMapJS (const tr) (const' fe) (const' fs) () ast
  where
    const' f _ x = ((),) <$> f x

instance JSTrav a => JSTrav [a] where
  foldMapJS tr fe fs acc ast =
      go (acc, []) ast
    where
      go (a, xs') (x:xs) = do
        (a', x') <- foldMapJS tr fe fs a x
        go (a', x':xs') xs
      go (a, xs) _ = do
        return (a, reverse xs)
  foldJS tr f acc ast = foldM (foldJS tr f) acc ast

instance JSTrav Exp where
  foldMapJS tr fe fs acc ast = do
      (acc', x) <- if tr acc (Exp ast False)
                     then do
                       case ast of
                         v@(Var _)      -> do
                           pure (acc, v)
                         l@(Lit _)      -> do
                           pure (acc, l)
                         l@(JSLit _)    -> do
                           pure (acc, l)
                         Not ex         -> do
                           fmap Not <$> mapEx acc ex
                         BinOp op a b   -> do
                           (acc', a') <- mapEx acc a
                           (acc'', b') <- mapEx acc' b
                           return (acc'', BinOp op a' b')
                         Fun vs stm     -> do
                           fmap (Fun vs) <$> foldMapJS tr fe fs acc stm
                         Call ar c f xs -> do
                           (acc', f') <- mapEx acc f
                           (acc'', xs') <- foldMapJS tr fe fs acc' xs
                           return (acc'', Call ar c f' xs')
                         Index arr ix   -> do
                           (acc', arr') <- mapEx acc arr
                           (acc'', ix') <- mapEx acc' ix
                           return (acc'', Index arr' ix')
                         Arr exs        -> do
                           fmap Arr <$> foldMapJS tr fe fs acc exs
                         AssignEx l r   -> do
                           (acc', l') <- mapEx acc l
                           (acc'', r') <- mapEx acc' r
                           return (acc'', AssignEx l' r')
                         IfEx c th el   -> do
                           (acc', c') <- mapEx acc c
                           (acc'', th') <- if tr acc (Exp th True)
                                             then mapEx acc' th
                                             else return (acc', th)
                           (acc''', el') <- if tr acc (Exp el True)
                                              then mapEx acc'' el
                                              else return (acc'', el)
                           return (acc''', IfEx c' th' el')
                         Eval x         -> do
                           fmap Eval <$> mapEx acc x
                         Thunk upd x    -> do
                           fmap (Thunk upd) <$> foldMapJS tr fe fs acc x
                     else do
                       return (acc, ast)
      fe acc' x
    where
      mapEx = foldMapJS tr fe fs
  
  foldJS tr f acc ast = do
    let expast = Exp ast False
    acc' <- if tr acc expast
              then do
                case ast of
                  Var _         -> do
                    return acc
                  Lit _         -> do
                    return acc
                  JSLit _       -> do
                    return acc
                  Not ex        -> do
                    foldJS tr f acc ex
                  BinOp _ a b  -> do
                    acc' <- foldJS tr f acc a
                    foldJS tr f acc' b
                  Fun _ stm      -> do
                    foldJS tr f acc stm
                  Call _ _ fun xs -> do
                    acc' <- foldJS tr f acc fun
                    foldJS tr f acc' xs
                  Index arr ix  -> do
                    acc' <- foldJS tr f acc arr
                    foldJS tr f acc' ix
                  Arr exs       -> do
                    foldJS tr f acc exs
                  AssignEx l r  -> do
                    acc' <- foldJS tr f acc l
                    foldJS tr f acc' r
                  IfEx c th el  -> do
                    acc' <- foldJS tr f acc c
                    acc'' <- if tr acc (Exp th True)
                               then foldJS tr f acc' th
                               else return acc'
                    if tr acc (Exp th True)
                      then foldJS tr f acc'' el
                      else return acc''
                  Eval ex       -> do
                    foldJS tr f acc ex
                  Thunk _upd stm -> do
                    foldJS tr f acc stm
              else do
                return acc
    f acc' expast

instance JSTrav Stm where
  foldMapJS tr fe fs acc ast = do
      (acc', x) <- if tr acc (Stm ast False)
                     then do
                       case ast of
                         Case ex def alts nxt -> do
                           (acc1, ex') <- foldMapJS tr fe fs acc ex
                           (acc2, def') <- foldMapJS tr fe fs acc1 def
                           (acc3, alts') <- foldMapJS tr fe fs acc2 alts
                           (acc4, nxt') <- if tr acc (Shared nxt)
                                             then foldMapJS tr fe fs acc3 nxt
                                             else return (acc3, nxt)
                           return (acc4, Case ex' def' alts' nxt')
                         Forever stm -> do
                           fmap Forever <$> foldMapJS tr fe fs acc stm
                         Assign lhs ex next -> do
                           (acc', lhs') <- foldMapJS tr fe fs acc lhs
                           (acc'', ex') <- foldMapJS tr fe fs acc' ex
                           (acc''', next') <- foldMapJS tr fe fs acc'' next
                           return (acc''', Assign lhs' ex' next')
                         Return ex -> do
                           fmap Return <$> foldMapJS tr fe fs acc ex
                         Cont -> do
                           return (acc, ast)
                         Stop -> do
                           return (acc, ast)
                         Tailcall ex -> do
                           fmap Tailcall <$> foldMapJS tr fe fs acc ex
                         ThunkRet ex -> do
                           fmap ThunkRet <$> foldMapJS tr fe fs acc ex
                     else do
                       return (acc, ast)
      fs acc' x

  foldJS tr f acc ast = do
    let stmast = Stm ast False
    acc' <- if tr acc stmast
              then do
                case ast of
                  Case ex def alts next -> do
                    acc' <- foldJS tr f acc ex
                    acc'' <- foldJS tr f acc' def
                    acc''' <- foldJS tr f acc'' alts
                    if tr acc (Shared next)
                      then foldJS tr f acc''' next
                      else return acc'''
                  Forever stm -> do
                    foldJS tr f acc stm
                  Assign lhs ex next -> do
                    acc' <- foldJS tr f acc lhs
                    acc'' <- foldJS tr f acc' ex
                    foldJS tr f acc'' next
                  Return ex -> do
                    foldJS tr f acc ex
                  Cont -> do
                    return acc
                  Stop -> do
                    return acc
                  Tailcall ex -> do
                    foldJS tr f acc ex
                  ThunkRet ex -> do
                    foldJS tr f acc ex
              else do
                return acc
    f acc' stmast

instance JSTrav (Exp, Stm) where
  foldMapJS tr fe fs acc (ex, stm) = do
    (acc', stm') <- if tr acc (Stm stm True)
                      then foldMapJS tr fe fs acc stm
                      else return (acc, stm)
    (acc'', ex') <- if tr acc (Exp ex True)
                      then foldMapJS tr fe fs acc' ex
                      else return (acc', ex)
    return (acc'', (ex', stm'))
  foldJS tr f acc (ex, stm) = do
    acc' <- if tr acc (Stm stm True)
              then foldJS tr f acc stm
              else return acc
    if tr acc (Exp ex True)
      then foldJS tr f acc' ex
      else return acc'

instance JSTrav LHS where
  foldMapJS _ _ _ acc lhs@(NewVar _ _) =
    return (acc, lhs)
  foldMapJS t fe fs a (LhsExp r ex) =
    fmap (LhsExp r) <$> foldMapJS t fe fs a ex
  foldJS _ _ acc (NewVar _ _)    = return acc
  foldJS tr f acc (LhsExp _ ex)  = foldJS tr f acc ex

-- | Returns the final statement of a line of statements.
finalStm :: Stm -> TravM Stm
finalStm = go
  where
    go (Case _ _ _ next) = go next
    go (Forever s)       = go s
    go (Assign _ _ next) = go next
    go s@(Return _)      = return s
    go s@Cont            = return s
    go s@Stop            = return s
    go s@(Tailcall _)    = return s
    go s@(ThunkRet _)    = return s

-- | Replace the final statement of the given AST with a new one, but only
--   if matches the given predicate.
replaceFinalStm :: Stm -> (Stm -> Bool) -> Stm -> TravM Stm
replaceFinalStm new p = go
  where
    go (Case c d as next) = Case c d as <$> go next
    go (Forever s)        = Forever <$> go s
    go (Assign l r next)  = Assign l r <$> go next
    go s@(Return _)       = return $ if p s then new else s
    go s@Cont             = return $ if p s then new else s
    go s@Stop             = return $ if p s then new else s
    go s@(Tailcall _)     = return $ if p s then new else s
    go s@(ThunkRet _)     = return $ if p s then new else s

-- | Returns statement's returned expression, if any.
finalExp :: Stm -> TravM (Maybe Exp)
finalExp stm = do
  end <- finalStm stm
  case end of
    Return ex -> return $ Just ex
    _         -> return Nothing

class Pred a where
  (.|.) :: a -> a -> a
  (.&.) :: a -> a -> a

instance Pred (a -> b -> Bool) where
  p .|. q = \a b -> p a b || q a b
  p .&. q = \a b -> p a b && q a b

instance Pred (a -> Bool) where
  p .|. q = \a -> p a || q a
  p .&. q = \a -> p a && q a

-- | Thunks and explicit lambdas count as lambda abstractions.
isLambda :: ASTNode -> Bool
isLambda (Exp (Fun _ _) _)   = True
isLambda (Exp (Thunk _ _) _) = True
isLambda _                   = False

isLoop :: ASTNode -> Bool
isLoop (Stm (Forever _) _) = True
isLoop _                   = False

isConditional :: ASTNode -> Bool
isConditional (Exp _ cond) = cond
isConditional (Stm _ cond) = cond
isConditional _            = False

isShared :: ASTNode -> Bool
isShared (Shared _) = True
isShared _          = False

isSafeForInlining :: ASTNode -> Bool
isSafeForInlining = not <$> isLambda .|. isLoop .|. isShared

-- | Counts occurrences. Use ints or something for a more exact count.
data Occs = Never | Once | Lots deriving (Eq, Show)

instance Ord Occs where
  compare Never Once = Prelude.LT
  compare Never Lots = Prelude.LT
  compare Once  Lots = Prelude.LT
  compare a b        = if a == b then Prelude.EQ else Prelude.GT

instance Num Occs where
  fromInteger n | n <= 0    = Never
                | n == 1    = Once
                | otherwise = Lots
  Never + x = x
  x + Never = x
  _ + _     = Lots

  Never * _ = Never
  _ * Never = Never
  Once * x  = x
  x * Once  = x
  _ * _     = Lots

  Never - _ = Never
  x - Never = x
  Once - _  = Never
  Lots - _  = Lots

  abs = id

  signum Never = Never
  signum _     = Once

-- | Replace all occurrences of an expression, without entering shared code
--   paths. IO ordering is preserved even when entering lambdas thanks to
--   State# RealWorld.
replaceEx :: JSTrav ast => (ASTNode -> Bool) -> Exp -> Exp -> ast -> TravM ast
replaceEx trav old new =
  mapJS trav (\x -> if x == old then pure new else pure x) pure

-- | Replace all occurrences of an expression, without entering shared code
--   paths. IO ordering is preserved even when entering lambdas thanks to
--   State# RealWorld.
replaceExWithCount :: JSTrav ast
                   => (ASTNode -> Bool) -- ^ Which nodes to enter?
                   -> Exp               -- ^ Expression to replace.
                   -> Exp               -- ^ Replacement expression.
                   -> ast               -- ^ AST to perform replacement on.
                   -> TravM (Int, ast)  -- ^ New AST + count of replacements.
replaceExWithCount trav old new ast =
    foldMapJS (const trav) rep (\count x -> return (count, x)) 0 ast
  where
    rep count ex
      | ex == old = return (count+1, new)
      | otherwise = return (count, ex)
