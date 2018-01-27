module Data.Transaction
  ( Transaction(..)
  , Flag(..)
  , Tag(..)
  ) where

import Control.Lens (makeLenses)
import Data.Decimal (Decimal)
import Data.Posting (Posting)
import Data.Text.Lazy (Text)
import Data.Time.Calendar (Day)

data Transaction = Transaction
  { _date :: Day
  , _flag :: Flag
  , _description :: Text
  , _tags :: [Tag]
  , _postings :: [Posting Decimal]
  } deriving (Eq, Show)

data Flag
  = Complete
  | Incomplete
  deriving (Eq, Show)

newtype Tag =
  Tag Text
  deriving (Show, Eq)

makeLenses ''Tag