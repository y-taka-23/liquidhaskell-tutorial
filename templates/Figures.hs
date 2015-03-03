{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE OverloadedStrings #-}
{-@ LIQUID "--no-termination" @-}

module Figures where

import Data.IORef
import Text.Pandoc.JSON
import Text.Pandoc
import Text.Pandoc.Walk (walkM)
import Data.List (isSuffixOf, isPrefixOf)
import Debug.Trace
import Text.Printf (printf)
 
-- import Data.Char (isSpace)
-- import Data.Monoid (mempty)
-- import System.Environment (getEnv)
 
import System.Directory
import System.IO
import Control.Applicative ((<$>))

import qualified Data.ByteString.Lazy as S
import qualified Data.Text as T
import qualified Data.Text.Lazy as L
import qualified Data.Text.IO as TIO
import qualified Data.Map as M
import Data.Maybe (fromMaybe)
import System.Environment (getEnv)

import Data.Text.Template

main :: IO ()
main = do tgt <- output <$> getEnv "PANDOC_TARGET"
          -- trace ("Pandoc OUTPUT: " ++ show tgt)
          txFig tgt

data Output = HTML | LATEX deriving (Eq)

instance Show Output where
  show HTML  = "html"
  show LATEX = "latex" 

output "html"  = HTML
output "latex" = LATEX
output s       = error $ "Figures : unknown target: " ++ s 

txFig HTML  = txFigures HTML  "../../" "templates/figHtml.template"
txFig LATEX = txFigures LATEX ""       "templates/figLatex.template"

                     
txFigures :: Output -> FilePath -> FilePath -> IO () 
txFigures tgt prefix templateF 
  = do r    <- newIORef emptyInfo 
       tplt <- TIO.readFile templateF 
       toJSONFilter (tx tgt (T.pack prefix) tplt r)

tx tgt prefix t r b0
  = do b1 <- txBlock tgt prefix t r b0
       b2 <- txLink               r b1
       return b2
              
txLink r = walkM (reLink r)

reLink   :: IORef Info -> Inline -> IO Inline
reLink r (Link [Str "auto"] tgt@('#':id,_))
  = do n <- getCount r id
       return $ Link [Str (show n)] tgt

reLink _ i
  = return i

txBlock _   _      _ r z@(Header 1 _ _)
  = newChapter r >> return z
    
txBlock tgt prefix t r (Div (id, [cls], kvs) _)
  | isFigure cls
  = makeFigure tgt prefix t r id cls kvs 
      
txBlock _ _ _ _ z
  = return z -- $ trace ("IAMTHIS:" ++ show z) z

isFigure s    = s `elem` ["figure", "marginfigure"]

makeFigure tgt prefix t r id cls kvs
  = RawBlock (Format $ show tgt) . pad prefix t id cls kvs <$> getCount r id
     
pad prefix tplt id cls kvs n
  = trace ("PAD" ++ show res) $ res 
  where
    res = L.unpack $ substitute tplt ctx 
    ctx          :: T.Text -> T.Text 
    ctx "class"  = T.pack cls 
    ctx "label"  = T.pack id 
    ctx "number" = T.pack $ show n
    ctx "file"   = T.append prefix  (get "file" kvs) 
    ctx str      = get (T.unpack str) kvs

get k kvs = T.pack
            $ fromMaybe (error $ "Cannot find: " ++ k )
            $ lookup k kvs

----------------------------------------------

data Info = Info { chapter :: Int
                 , count   :: Int
                 , label   :: M.Map String Int
                 }
            deriving (Show)

data Ref  = Ref Int Int

instance Show Ref where
  show (Ref i j) = show i ++ "." ++ show j
  
emptyInfo
  = Info 0 1 M.empty

getCount r id
  = do info <- readIORef r
       let m  = label info
       let c  = chapter info 
       let i  = count info
       let n  = M.findWithDefault i id m
       let i' = if i == n then i + 1 else i 
       let l  = Ref c n 
       writeIORef r (info {count = i', label = M.insert id n m})
       return $ trace ("GETCOUNT: " ++ show l) l 

newChapter r
  = do info <- readIORef r
       writeIORef r (info {count = 1, chapter = 1 + chapter info})
