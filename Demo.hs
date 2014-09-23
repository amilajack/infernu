module Main where

import System.Environment(getArgs)
import Text.PrettyPrint.GenericPretty(pp, Out(..))
import Control.Arrow((***))

import qualified Language.ECMAScript3.PrettyPrint as ES3PP
import qualified Language.ECMAScript3.Parser as ES3Parser
import qualified Language.ECMAScript3.Syntax as ES3

import Infer
import Pretty
import Types

-- ------------------------------------------------------------------------

ex :: Body (Expr ()) -> Expr ()
ex expr = Expr expr ()


st :: Body (Expr ()) -> Statement (Expr ())
st expr = Expression $ ex expr


fromStatement :: ES3.Statement a -> Statement (Expr ())
fromStatement (ES3.BlockStmt _ stmts) = Block $ map fromStatement stmts
fromStatement (ES3.EmptyStmt _) = Empty
fromStatement (ES3.ExprStmt _ e) = Expression $ fromExpression e
fromStatement (ES3.IfStmt _ pred' thenS elseS) = IfThenElse (fromExpression pred') (fromStatement thenS) (fromStatement elseS)
fromStatement (ES3.IfSingleStmt _ pred' thenS) = IfThenElse (fromExpression pred') (fromStatement thenS) Empty
fromStatement (ES3.WhileStmt _ pred' stmt) = While (fromExpression pred') (fromStatement stmt)
fromStatement (ES3.ReturnStmt _ x) = Return . fmap fromExpression $ x
--fromStatement (ES3.LabelledStmt _ _ s) =
--fromStatement (ES3.ForInStmt _ x) = 
fromStatement (ES3.ForStmt _ forInit pred' incr stmt) = 
    Block [ fromForInit forInit
          , While (maybe (ex $ LitBoolean True) fromExpression pred') 
                      (Block $ fromStatement stmt : incr'')
          ]
    where incr'' = maybe [] (\x -> [Expression $ fromExpression x]) incr
fromStatement (ES3.VarDeclStmt _ decls) = Block $ concatMap fromVarDecl decls
fromStatement (ES3.FunctionStmt _ name args stmts) = Expression . ex $ LitFunc (Just . ES3.unId $ name) (map ES3.unId args) (map fromStatement stmts)
fromStatement s = error $ "Not implemented statment: " ++ show (ES3PP.prettyPrint s)



fromVarDecl :: ES3.VarDecl a -> [Statement (Expr ())]
fromVarDecl (ES3.VarDecl _ id' assignRValue) = declS : assignS
    where declS = VarDecl varName
          varName = ES3.unId id'
          assignS = case assignRValue of
                      Nothing -> []
                      Just ex' -> [Expression . ex $ Assign (ex $ Var varName) (fromExpression ex')]

fromForInit :: ES3.ForInit a -> Statement (Expr ())
fromForInit ES3.NoInit = Empty
--fromForInit (ES3.VarInit varDecls) = Block $ map fromVarDecl varDecls
fromForInit (ES3.ExprInit expr) = Expression $ fromExpression expr
--fromStatement

-- fromVarDecl :: ES3.VarDecl a -> Statement (Expr ())
-- fromVarDecl (VarDecl _ (Id _ name) expr) = 
--     case expr of
--       Nothing -> 

fromExpression :: ES3.Expression a -> Expr ()
fromExpression es3x = 
    ex $ case es3x of
      ES3.StringLit _ s -> LitString s
      ES3.RegexpLit _ s _ _ -> LitRegex s
      ES3.NumLit _ x -> LitNumber x
      ES3.IntLit _ x -> LitNumber $ fromIntegral x
      ES3.BoolLit _ x -> LitBoolean x
      ES3.ArrayLit _ xs -> LitArray $ map fromExpression xs
      ES3.ObjectLit _ props -> LitObject $ map (fromProp *** fromExpression) props
      ES3.FuncExpr _ name argNames stmts -> LitFunc (fmap ES3.unId name) (map ES3.unId argNames) (map fromStatement stmts) 
      ES3.VarRef _ name -> Var $ ES3.unId name
      ES3.DotRef _ expr name -> Property (fromExpression expr) (ES3.unId name)
      ES3.AssignExpr _ ES3.OpAssign lvalue expr -> Assign (fromLValue lvalue) (fromExpression expr)
      ES3.CallExpr _ expr argExprs -> Call (fromExpression expr) $ map fromExpression argExprs
      _ -> error $ "not implemented: " ++ show (ES3PP.prettyPrint es3x)

fromLValue :: ES3.LValue a -> Expr ()
fromLValue (ES3.LVar _ name) = ex $ Var name
fromLValue (ES3.LDot _ expr str) = ex $ Property (fromExpression expr) str
fromLValue (ES3.LBracket _ x y) = ex $ Index (fromExpression x) (fromExpression y)


fromProp :: ES3.Prop a -> String
fromProp (ES3.PropId _ (ES3.Id _ x)) = x
fromProp (ES3.PropString _ x) = x
fromProp (ES3.PropNum _ x) = show x


-- printInferredExprType :: Either TypeError InferredExpr -> String
-- printInferredExprType (Right t) = incomment . toJsDoc . exprData $ t
-- printInferredExprType (Left x) = incomment . show $ x

printType :: Statement (Expr JSType) -> IO ()
printType stmt = putStrLn $ toJsSt (incomment . toJsDoc) 0 stmt

instance (Out a) => Out (Body a)
instance (Out a) => Out (Expr a)
instance (Out a) => Out (Statement a)
instance (Out a) => Out (TypeError a)

main :: IO ()
main = do
  args <- getArgs
  let arg = head args
  js <- ES3Parser.parseFromFile arg 
--  putStrLn . show $ js
  let stmts = map fromStatement $ ES3.unJavaScript js
--  pp $ Block . flattenBlocks $ stmts
  let inf = runInfer $ inferStatement . flattenBlocks . Block $ stmts
  pp inf
  case inf of
    Left err' -> print err'
    Right inf' -> printType inf'
--  toJsSt $ fst inf


-- idE = ex $ LitFunc ["arg"] [ Return . Just . ex $ Var "arg", VarDecl "var1", st $ Assign (ex $ Var "var1") (ex $ LitNumber 1), Return . Just . ex $ Var "arg" ]
-- idT = runState (inferType idE) emptyScope

-- e1 = ex $ LitFunc ["arg"]
--      $ [ VarDecl "vari"
--        , st $ Assign (ex $ Var "vari") (ex $ LitObject [("amount", ex $ LitNumber 123)])
--        , While (ex $ LitBoolean False) (st $ Assign (ex $ Property (ex $ Var "vari") "amount") (ex $ LitNumber 0))
--    --    , ex $ Assign (ex $ Var "vari") (ex $ LitString "ma?")
--        , IfThenElse (ex $ LitBoolean False) (Return $ Just . ex $ LitArray []) (Return $ Just . ex $ LitArray [ex $ LitObject [("bazooka", ex $ Var "arg"), ("number", ex $ Var "vari")]])]
-- --e1 = ex $ LitFunc ["arg"] ["vari"] []

-- t1 = inferType e1
-- s1 = runState t1 emptyScope
-- s1doc = toJsDoc . fromJust . getExprType $ fst s1

-- e2 = ex $ Property (ex $ Index (ex $ Call e1 [(ex $ LitString "abc")]) (ex $ LitNumber 2)) "number"
-- s2 = runState (inferType e2) emptyScope


-- e3 = ex $ Assign (ex $ Var "f") e1
-- s3 = runState (inferType e3) emptyScope

-- arrayTest = ex $ Index (ex $ LitArray [ex $ LitBoolean False, ex $ LitBoolean True]) (ex $ LitNumber 32)

-- infArrayTest = runInfer $ inferExpr arrayTest

-- funcTest = ex $ LitFunc (Just "myFunc") ["x", "y"] [Expression . ex $ Call (ex $ Var "x") [(ex $ Var "y")]]

-- infFuncTest = runInfer $ inferExpr funcTest

-- failFuncTest = ex $ LitFunc (Just "myFunc") ["x"] [Expression . ex $ Call (ex $ Var "x") [ex $ Var "x"]]

-- infFailFuncTest = runInfer $ inferExpr failFuncTest

