module Beans.CLI
  ( balanceOptions, importOptions
  ) where

import           Beans.Options       (BalanceOptions (..), ImportOptions (..),
                                      ReportType (..))
import qualified Beans.Parser        as P
import           Data.Semigroup      ((<>))
import qualified Data.Text           as T
import           Data.Time.Calendar  (Day)
import           Options.Applicative
import           Text.Megaparsec     (parse, parseErrorPretty)


toReadM :: P.Parser a -> ReadM a
toReadM p = eitherReader $ parse' p "" . T.pack
 where
  parse' parser input s = case parse parser input s of
    Left  e -> Left $ parseErrorPretty e
    Right d -> Right d


dateparser :: String -> String -> Parser (Maybe Day)
dateparser optionStr helpStr = optional $ option
  (toReadM P.date)
  (long optionStr <> help helpStr <> metavar "YYYY-MM-DD")

parseReportType :: ReadM ReportType
parseReportType = eitherReader $ \case
  "hierarchical" -> Right Hierarchical
  "flat"         -> Right Flat
  s              -> Left $ "Invalid report type: " <> s

reportType :: Parser ReportType
reportType = option
  parseReportType
  (  value Hierarchical
  <> help "The type of the report"
  <> long "report-type"
  <> metavar "(flat|hierarchical)"
  <> short 'r'
  )

balanceOptions :: Parser BalanceOptions
balanceOptions =
  BalanceOptions
    <$> argument
          str
          ( value "journal.bean" <> metavar "JOURNAL" <> help
            "The journal file to parse"
          )
    <*> optional (option (toReadM P.commodity) (long "convert" <> short 'c'))
    <*> switch (long "lots" <> short 'l' <> help "Show lots")
    <*> dateparser "from" "Consider only transactions at or after this date"
    <*> dateparser "to"   "Consider only transaction before or at this date"
    <*> optional
          ( option
            auto
            (  metavar "DEPTH"
            <> help "summarize accounts at this level"
            <> long "depth"
            <> short 'd'
            )
          )
    <*> optional
          ( strOption
            (  metavar "REGEX"
            <> help "A regular expression to filter the accounts"
            <> long "filter"
            <> short 'f'
            )
          )
    <*> switch
          (  long "strict-filter"
          <> short 's'
          <> help
               "If enabled, strict filtering will filter all postings which don't match. If disabled (default), only transactions are filtered."
          )
    <*> reportType

importOptions :: Parser ImportOptions
importOptions =
  ImportOptions
    <$> strOption
          ( metavar "IMPORTER" <> short 'i' <> help
            "Currently: only ch.postfinance"
          )
    <*> strOption
          (  metavar "CONFIG_FILE"
          <> help "The configuration to use"
          <> short 'c'
          <> long "config"
          )
    <*> option (toReadM P.account)
               (metavar "ACCOUNT" <> long "account" <> short 'a')
    <*> argument str (metavar "<data file>" <> help "The data file to parse")