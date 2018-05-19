module Haricot.Valuation where

import           Control.Monad.Catch      (MonadThrow)
import           Control.Monad.State      (MonadState, evalStateT, execStateT,
                                           get, gets, put)
import qualified Data.Map.Strict.Extended as M
import           Data.Maybe               (catMaybes)
import           Data.Scientific          (Scientific)
import           Data.Time.Calendar       (Day, fromGregorian)
import           Haricot.Accounts         (Accounts, RestrictedAccounts (..),
                                           Restrictions, updateAccounts)
import           Haricot.AST              (AccountName (..), Balance (..),
                                           CommodityName (..), Flag (..),
                                           Lot (..), Open (..), Posting (..),
                                           Restriction (..), Transaction (..))
import           Haricot.Ledger           (Ledger, Timestep (..))
import           Haricot.Prices           (NormalizedPrices, Prices,
                                           lookupPrice, normalize, updatePrices)

data ValuationState = ValuationState
  { _prices               :: Prices
  , _prevNormalizedPrices :: NormalizedPrices
  , _normalizedPrices     :: NormalizedPrices
  , _prevAccounts         :: Accounts
  , _accounts             :: Accounts
  , _restrictions         :: Restrictions
  , _target               :: CommodityName
  , _valuationAccount     :: AccountName
  , _date                 :: Day
  }

calculateValuation :: MonadThrow m => CommodityName -> AccountName -> Ledger -> m Ledger
calculateValuation _target _valuationAccount ledger =
  evalStateT
     (mapM convertTimestep ledger)
     ValuationState
        { _prices = mempty
        , _prevNormalizedPrices = mempty
        , _normalizedPrices = mempty
        , _prevAccounts = mempty
        , _accounts = mempty
        , _restrictions = mempty
        , _date = fromGregorian 1900 1 1
        , ..
        }

convertTimestep ::
     (MonadThrow m, MonadState ValuationState m)
  => Timestep
  -> m Timestep
convertTimestep timestep@Timestep {..} = do
  ValuationState {..} <- get
  RestrictedAccounts _accounts' _restrictions' <-
    execStateT
      (updateAccounts timestep)
      (RestrictedAccounts _accounts _restrictions)
  let _prices' = updatePrices timestep _prices
  put
    ValuationState
      { _prices = _prices'
      , _prevNormalizedPrices = _normalizedPrices
      , _normalizedPrices = normalize _prices' _target
      , _prevAccounts = _accounts
      , _accounts = _accounts'
      , _restrictions = _restrictions'
      , ..
      }
  convertedOpenings <- mapM convertOpening _openings
  convertedBalances <- mapM convertBalance _balances
  convertedTransactions <- mapM convertTransaction _transactions
  valuationTransactions <- adjustValuationForAccounts
  return $
    timestep
      { _balances = convertedBalances
      , _transactions = convertedTransactions ++ valuationTransactions
      , _openings = convertedOpenings
      }

convertOpening :: MonadState ValuationState m => Open -> m Open
convertOpening o = do
  t <- gets _target
  return $ o {_restriction = RestrictedTo [t]}

convertBalance ::
     (MonadThrow m, MonadState ValuationState m) => Balance -> m Balance
convertBalance Balance {..} = do
  ValuationState {_target, _prevNormalizedPrices} <- get
  price <- lookupPrice _commodity _prevNormalizedPrices
  return Balance {_amount = _amount * price, _commodity = _target, ..}

convertTransaction ::
     (MonadThrow m, MonadState ValuationState m)
  => Transaction
  -> m Transaction
convertTransaction Transaction {..} = do
  ValuationState { _valuationAccount, _normalizedPrices } <- get
  postings <- mapM (convertPosting _normalizedPrices) _postings
  let balancePostings = map (f _valuationAccount) (calculateImbalances postings)
  return Transaction {_postings = postings ++ balancePostings, ..}
  where
    f _account (_commodity, amount) =
      Posting {_pos = Nothing, _amount = negate amount, _lot = NoLot, ..}


calculateImbalances :: [Posting] -> [(CommodityName, Scientific)]
calculateImbalances =
  M.toList . M.filter ((> 0.005) . abs) . M.fromListWith (+) . fmap weight
  where
    weight Posting {..} = (_commodity, _amount)

convertPosting ::
     (MonadThrow m, MonadState ValuationState m)
  => NormalizedPrices
  -> Posting
  -> m Posting
convertPosting prices Posting {..} = do
  tc <- gets _target
  if tc == _commodity
    then return Posting {..}
    else do
      price <- lookupPrice _commodity prices
      return Posting {_amount = _amount * price, _commodity = tc, ..}

adjustValuationForAccounts ::
     (MonadThrow m, MonadState ValuationState m)
  => m [Transaction]
adjustValuationForAccounts  = do
  ValuationState { _prevAccounts, _date } <- get
  s <- sequence $ M.mapWithKey adjustValuationForAccount _prevAccounts
  return $ catMaybes $ M.toListWith snd s

adjustValuationForAccount ::
     (MonadThrow m, MonadState ValuationState m)
  => (AccountName, CommodityName, Lot)
  -> Scientific
  -> m (Maybe Transaction)
adjustValuationForAccount (a, c, l) s = do
  ValuationState { _target
                 , _date
                 , _valuationAccount
                 , _prevNormalizedPrices
                 , _normalizedPrices
                 } <- get
  v0 <- lookupPrice c _prevNormalizedPrices
  v1 <- lookupPrice c _normalizedPrices
  if v0 == v1
    then return Nothing
    else Just <$> createValuationTransaction a l (s * (v1 - v0))

createValuationTransaction ::
     MonadState ValuationState m
  => AccountName
  -> Lot
  -> Scientific
  -> m Transaction
createValuationTransaction _account _lot _amount = do
  ValuationState {_target, _date, _valuationAccount} <- get
  return
    Transaction
      { _pos = Nothing
      , _flag = Complete
      , _description = "valuation"
      , _tags = []
      , _date
      , _postings =
          [ Posting
              {_pos = Nothing, _account, _commodity = _target, _amount, _lot}
          , Posting
              { _pos = Nothing
              , _account = _valuationAccount
              , _commodity = _target
              , _amount = -_amount
              , _lot = NoLot
              }
          ]
      }
