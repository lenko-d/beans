{-# LANGUAGE GADTs #-}

module Beans.Import.DSL where

import           Beans.Model                    ( Account(..)
                                                , Date
                                                , Amount
                                                , Date
                                                , Commodity
                                                )
import           Control.Exception              ( Exception )
import           Control.Monad                  ( msum )
import           Control.Monad.Catch            ( MonadThrow
                                                , throwM
                                                )
import           Control.Monad.IO.Class         ( MonadIO
                                                , liftIO
                                                )
import           Control.Monad.Reader           ( Reader
                                                , asks
                                                , runReaderT
                                                )
import           Control.Applicative            ( (<**>) )
import           Data.Bool                      ( bool )
import           Data.Functor.Identity          ( runIdentity )
import           Data.Monoid                    ( (<>) )
import           Data.Char                      ( isAlphaNum )
import           Data.Text                      ( Text
                                                , cons
                                                , pack
                                                , unpack
                                                )
import           Data.Text.IO                   ( readFile )
import           Data.Void                      ( Void )
import           Prelude                 hiding ( readFile )
import           Beans.Megaparsec               ( Parsec
                                                , between
                                                , choice
                                                , empty
                                                , notFollowedBy
                                                , eof
                                                , many
                                                , parse
                                                , errorBundlePretty
                                                , parseAmount
                                                , parseISODate
                                                , parseAccount
                                                , takeWhileP
                                                , try
                                                , char
                                                , letterChar
                                                , symbolChar
                                                , space1
                                                , string
                                                )
import qualified Text.Megaparsec.Char.Lexer    as L
import           Control.Monad.Combinators.Expr ( Operator(InfixL, Prefix)
                                                , makeExprParser
                                                )
import           Text.Regex.PCRE                ( (=~) )

-- Abstract Syntax Tree
type Rules = [Rule]

data Rule =
  Rule (E Bool)
       Account
  deriving (Show)

data E a where
  EVarAmount ::E Amount
  EVarDescription ::E Text
  EVarType ::E Text
  EVarDate ::E Date
  EVarImporter ::E Text
  EDate ::Date -> E Date
  EAmount ::Amount -> E Amount
  EText ::Text -> E Text
  EBool ::Bool -> E Bool
  EAnd ::E Bool -> E Bool -> E Bool
  EOr ::E Bool -> E Bool -> E Bool
  ENot ::E Bool -> E Bool
  EPlus ::Num a => E a -> E a -> E a
  EMinus ::Num a => E a -> E a -> E a
  EAbs ::Num a => E a -> E a
  ELT ::(Show a, Ord a) => E a -> E a -> E Bool
  ELE ::(Show a, Ord a) => E a -> E a -> E Bool
  EEQ ::(Show a, Eq a) => E a -> E a -> E Bool
  EGE ::(Show a, Ord a) => E a -> E a -> E Bool
  EGT ::(Show a, Ord a) => E a -> E a -> E Bool
  ENE ::(Show a, Ord a) => E a -> E a -> E Bool
  EMatch ::E Text -> E Text -> E Bool

instance Show a => Show (E a) where
  show (EBool   a)     = show a
  show (EText   a)     = show a
  show (EDate   a)     = show a
  show (EAmount a)     = show a
  show EVarAmount      = "amount"
  show EVarType        = "type"
  show EVarDescription = "description"
  show EVarDate        = "date"
  show EVarImporter    = "importer"
  show (EAbs a    )    = "abs(" <> show a <> ")"
  show (EAnd a b  )    = "(" <> show a <> " && " <> show b <> ")"
  show (EOr  a b  )    = "(" <> show a <> " || " <> show b <> ")"
  show (ENot a    )    = "!" <> show a
  show (EPlus  x y)    = "(" <> show x <> " + " <> show y <> ")"
  show (EMinus x y)    = "(" <> show x <> " - " <> show y <> ")"
  show (ELT    a b)    = "(" <> show a <> " < " <> show b <> ")"
  show (ELE    a b)    = "(" <> show a <> " <= " <> show b <> ")"
  show (EEQ    a b)    = "(" <> show a <> " == " <> show b <> ")"
  show (EGE    a b)    = "(" <> show a <> " >= " <> show b <> ")"
  show (EGT    a b)    = "(" <> show a <> " > " <> show b <> ")"
  show (ENE    a b)    = "(" <> show a <> " <> " <> show b <> ")"
  show (EMatch a b)    = "(" <> show a <> " =~ " <> show b <> ")"

-- Evaluation


data Context = Context
  { _contextDate :: Date
  , _contextBookingType :: Text
  , _contextDescription :: Text
  , _contextAmount      :: Amount
  , _contextCommodity   :: Commodity
  , _contextImporter    :: Text
  } deriving (Eq, Show)

type Evaluator = Context -> Maybe Account

evaluate :: Traversable t => t Rule -> Context -> Maybe Account
evaluate r = runIdentity . runReaderT (evalRules r)

evalRules :: Traversable t => t Rule -> Reader Context (Maybe Account)
evalRules rs = msum <$> sequence (evalRule <$> rs)

evalRule :: Rule -> Reader Context (Maybe Account)
evalRule (Rule e c) = bool Nothing (Just c) <$> evalE e

evalE :: E a -> Reader Context a
evalE (EBool   a)     = return a
evalE (EText   a)     = return a
evalE (EDate   a)     = return a
evalE (EAmount a)     = return a
evalE EVarAmount      = asks _contextAmount
evalE EVarDescription = asks _contextDescription
evalE EVarType        = asks _contextBookingType
evalE EVarDate        = asks _contextDate
evalE EVarImporter    = asks _contextImporter
evalE (EAbs a    )    = abs <$> evalE a
evalE (EAnd a b  )    = (&&) <$> evalE a <*> evalE b
evalE (EOr  a b  )    = (||) <$> evalE a <*> evalE b
evalE (ENot a    )    = not <$> evalE a
evalE (EPlus  x y)    = (+) <$> evalE x <*> evalE y
evalE (EMinus x y)    = (-) <$> evalE x <*> evalE y
evalE (ELT    a b)    = (<) <$> evalE a <*> evalE b
evalE (ELE    a b)    = (<=) <$> evalE a <*> evalE b
evalE (EEQ    a b)    = (==) <$> evalE a <*> evalE b
evalE (EGE    a b)    = (>=) <$> evalE a <*> evalE b
evalE (EGT    a b)    = (>) <$> evalE a <*> evalE b
evalE (ENE    a b)    = (/=) <$> evalE a <*> evalE b
evalE (EMatch t regex) =
  (=~) <$> (unpack <$> evalE t) <*> (unpack <$> evalE regex)

-- Parser
type Parser = Parsec Void Text

-- The exception exported by this module
newtype ParserException =
  ParserException String
  deriving (Eq)

instance Show ParserException where
  show (ParserException s) = s

instance Exception ParserException

-- parse a file of rules
parseFile :: (MonadIO m, MonadThrow m) => FilePath -> m Rules
parseFile filePath = (liftIO . readFile) filePath >>= parseSource
 where
  parseSource input = either (throwM . ParserException . errorBundlePretty)
                             return
                             (parse rules filePath input)

sc :: Parser ()
sc = L.space space1 lineComment empty
  where lineComment = L.skipLineComment "#"

lexeme :: Parser a -> Parser a
lexeme = L.lexeme sc

sym :: Text -> Parser Text
sym = L.symbol sc

parens :: Parser a -> Parser a
parens = between (sym "(") (sym ")")

identifier :: Parser Text
identifier =
  cons <$> letterChar <*> takeWhileP (Just "alphanumeric") isAlphaNum

account :: Parser Account
account = lexeme parseAccount

rules :: Parser Rules
rules = between sc eof (many rule)

rule :: Parser Rule
rule = Rule <$> boolExpr <* sym "->" <*> account

amountLiteral :: Parser (E Amount)
amountLiteral = lexeme $ EAmount <$> parseAmount sc

textLiteral :: Parser (E Text)
textLiteral = EText <$> lexeme quotedText
 where
  quotedText = between quote quote (takeWhileP (Just "no quote") (/= '"'))
  quote      = char '"'

dateLiteral :: Parser (E Date)
dateLiteral = (try . lexeme . fmap EDate) parseISODate

boolLiteral :: Parser (E Bool)
boolLiteral = EBool <$> choice [True <$ sym "True", False <$ sym "False"]

textExpr :: Parser (E Text)
textExpr = choice
  [ parens textExpr
  , textLiteral
  , EVarDescription <$ sym "description"
  , EVarType <$ sym "type"
  , EVarImporter <$ sym "importer"
  ]

textRelation :: Parser (E Text -> E Text -> E Bool)
textRelation = choice [EEQ <$ sym "==", ENE <$ sym "!=", EMatch <$ sym "=~"]

dateExpr :: Parser (E Date)
dateExpr = choice [parens dateExpr, dateLiteral, EVarDate <$ sym "date"]

amountExpr :: Parser (E Amount)
amountExpr = makeExprParser amountTerm amountOperators
 where
  amountTerm =
    choice [parens amountExpr, amountLiteral, EVarAmount <$ sym "amount"]
  amountOperators =
    [ [Prefix (EAbs <$ sym "abs")]
    , [InfixL (EPlus <$ sym "+"), InfixL (EMinus <$ op "-")]
    ]

op :: Text -> Parser Text
op n = (lexeme . try) (string n <* notFollowedBy symbolChar)

boolExpr :: Parser (E Bool)
boolExpr = makeExprParser boolTerm boolOperators
 where
  boolTerm = choice
    [parens boolExpr, boolLiteral, dateRelExpr, amountRelExpr, textRelExpr]
  boolOperators =
    [ [Prefix (ENot <$ sym "!")]
    , [InfixL (EAnd <$ sym "&&")]
    , [InfixL (EOr <$ sym "||")]
    ]
  amountRelExpr = comparison amountExpr relation
  textRelExpr   = comparison textExpr textRelation
  dateRelExpr   = comparison dateExpr relation

comparison :: (Applicative f) => f a -> f (a -> a -> b) -> f b
comparison expr rel = expr <**> rel <*> expr

relation :: (Show a, Ord a) => Parser (E a -> E a -> E Bool)
relation = choice
  [ ELE <$ sym "<="
  , EGE <$ sym ">="
  , EGT <$ sym ">"
  , ELT <$ sym "<"
  , EEQ <$ sym "=="
  , ENE <$ sym "!="
  ]
