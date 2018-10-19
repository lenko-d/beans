module Beans.Report.Journal
  ( createReport
  , Report(..)
  , reportToTable
  )
where

import qualified Data.Text                     as T
import           Text.Regex.PCRE                          ( (=~) )
import           Beans.Data.Directives                    ( Command(..)
                                                          , Dated(..)
                                                          )
import           Beans.Options                            ( JournalOptions(..)
                                                          , Filter(..)
                                                          )
import           Beans.Ledger                             ( Ledger )
import           Beans.Data.Accounts                      ( Date(..)
                                                          , Amount
                                                          , Accounts
                                                          , Commodity
                                                          , Position(..)
                                                          , Account
                                                          , format
                                                          )
import qualified Data.List                     as List
import           Beans.Accounts                           ( calculateAccountsForDays
                                                          )
import qualified Beans.Ledger                  as L
import qualified Beans.Data.Map                as M
import           Data.Text                                ( Text )
import           Control.Monad.Catch                      ( MonadThrow )
import           Data.Maybe                               ( mapMaybe )
import           Beans.Table                              ( Cell(..) )

data Report = Report {
  rHeader :: Dated Item,
  rItems :: M.Map Date [Item],
  rFooter :: Dated Item
  } deriving (Show)

data Item = Item {
  eDescription :: Text,
  eAccountPostings :: [(Commodity, Amount)],
  eOtherPostings :: [(Account, Commodity, Amount)]
  } deriving (Show)

createReport :: MonadThrow m => JournalOptions -> Ledger -> m Report
createReport JournalOptions {..} ledger = do
  let filtered = L.filter (Filter (T.unpack jrnOptRegex)) ledger
      items    = mapMaybe (toItem jrnOptRegex)
        $ L.filter (PeriodFilter jrnOptFrom jrnOptTo) filtered
  [accounts0, accounts1] <- calculateAccountsForDays filtered
                                                     [jrnOptFrom, jrnOptTo]
                                                     mempty
  return $ Report
    { rHeader = accountsToItem jrnOptRegex jrnOptFrom accounts0
    , rItems  = M.fromListM items
    , rFooter = accountsToItem jrnOptRegex jrnOptTo accounts1
    }

accountsToItem :: Text -> Date -> Accounts -> Dated Item
accountsToItem regex date accounts =
  let filteredAccounts =
        List.filter ((=~ T.unpack regex) . show . pAccount . fst)
          $ M.toList accounts
      amounts = M.toList $ mconcat (snd <$> filteredAccounts)
  in  Dated
        date
        (Item
          { eDescription     = regex
          , eAccountPostings = amounts
          , eOtherPostings   = []
          }
        )

toItem :: Text -> Dated Command -> Maybe (Date, [Item])
toItem regex (Dated d Transaction { tDescription, tPostings })
  = let (accountPostings, otherPostings) =
          List.partition ((=~ T.unpack regex) . show . pAccount . fst)
            $ M.toList tPostings
    in  Just
          ( d
          , [ Item
                { eDescription     = tDescription
                , eAccountPostings = concat
                  $   toAccountPostings
                  <$> accountPostings
                , eOtherPostings   = concat $ toOtherPostings <$> otherPostings
                }
            ]
          )
 where
  toAccountPostings (_, amounts) = M.toList amounts
  toOtherPostings (Position {..}, amounts) = f pAccount <$> M.toList amounts
  f a (commodity, amount) = (a, commodity, amount)
toItem _ _ = Nothing


-- Formatting a report into rows
reportToTable :: Report -> [[Cell]]
reportToTable (Report (Dated t0 header) items (Dated t1 footer)) = concat
  [ [replicate 7 Separator]
  , itemToRows ((AlignLeft . T.pack . show) t0) header
  , [replicate 7 Separator]
  , (concatMap datedItemToRows . M.toList) items
  , [replicate 7 Separator]
  , itemToRows ((AlignLeft . T.pack . show) t1) footer
  , [replicate 7 Separator]
  ]

datedItemToRows :: (Date, [Item]) -> [[Cell]]
datedItemToRows (d, items) =
  concat
      (zipWith itemToRows ((AlignLeft . T.pack . show) d : repeat Empty) items)
    ++ [replicate 7 Empty]

itemToRows :: Cell -> Item -> [[Cell]]
itemToRows date Item {..} =
  let
    dates    = take nbrRows $ date : repeat Empty
    desc     = T.chunksOf 40 eDescription
    quantify = take nbrRows . (++ repeat "")
    amounts  = AlignRight <$> quantify (format . snd <$> eAccountPostings)
    commodities =
      AlignLeft <$> quantify (T.pack . show . fst <$> eAccountPostings)
    descriptions  = AlignLeft <$> quantify desc
    otherAccounts = AlignLeft <$> quantify
      (T.pack . show . (\(account, _, _) -> account) <$> eOtherPostings)
    otherAmounts = AlignRight
      <$> quantify (format . (\(_, _, amount) -> amount) <$> eOtherPostings)
    otherCommodities = AlignLeft <$> quantify
      (T.pack . show . (\(_, commodity, _) -> commodity) <$> eOtherPostings)
    nbrRows = maximum [1, length eAccountPostings, length eOtherPostings]--, length desc]
  in
    List.transpose
      [ dates
      , amounts
      , commodities
      , descriptions
      , otherAccounts
      , otherAmounts
      , otherCommodities
      ]
