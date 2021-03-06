{-# LANGUAGE OverloadedStrings #-}
import Codec.MIME.Type (Type(..), MIMEType(..), MIMEParam(..))
import Codec.MIME.Parse (parseContentType)
import Control.Concurrent.MVar (newMVar, MVar, withMVar)
import Control.Monad.IO.Class (liftIO)
import Data.ByteString.Lazy (ByteString)
import Data.Encoding (encodingFromStringExplicit, decodeLazyByteStringExplicit)
import Data.Maybe (listToMaybe, fromMaybe)
import Data.Monoid (mconcat)
import Data.Text.Lazy (Text, pack, unpack, toLower, toStrict, fromStrict, replace)
import Data.Text.Lazy.IO (hPutStr)
import Data.Version (showVersion)
import Network.HTTP.Types (ok200, badRequest400, unsupportedMediaType415,
    methodNotAllowed405)
import Network.Wai.Handler.Warp (setHost, setPort, defaultSettings, Port)
import System.Environment (getArgs, getProgName)
import System.Exit (exitWith, ExitCode(..))
import System.IO (stderr, hPutStrLn, withFile, IOMode(AppendMode), Handle,
    hFlush, FilePath, hSetNewlineMode, universalNewlineMode)
import Web.Scotty (scottyOpts, Options(..), ScottyM, ActionM, post, header,
    body, text, status)

import Paths_logserver (version)

main = do
    args <- getArgs
    progname <- getProgName
    case parseArgs progname args of
        Left err -> do
            hPutStrLn stderr err
            exitWith $ ExitFailure 2
        Right ShowVersion ->
            putStrLn $ "logserver-" ++ (showVersion version)
        Right (RunServer port filename) ->
            withFile filename AppendMode $ \h -> do
                hSetNewlineMode h universalNewlineMode
                mh <- newMVar h
                scottyOpts Options{ verbose = 0
                                  , settings = setHost "127.0.0.1"
                                             $ setPort port
                                             $ defaultSettings
                                  }
                            (app mh)

app :: MVar Handle -> ScottyM ()
app log = do
    post "/" $ do
        hdr <- header "Content-Type"
        bod <- body
        case getText hdr bod of
            Left err -> err
            Right txt -> do
                liftIO $ withMVar log $ \h -> do
                    hPutStr h txt
                    hFlush h
                status ok200
                text "Logged.\r\n"

getText :: Maybe Text -> ByteString -> Either (ActionM ()) Text
getText maybeContentType bs = do
    case fmap mimeType contentType of
        Nothing -> Left $ do status badRequest400
                             text $ mconcat [ "Incomprehensible Content-Type: "
                                            , contentTypeT
                                            , "\r\n" ]
        Just (Text _) -> return ()
        _ -> Left $ do status unsupportedMediaType415
                       text $ mconcat [ "Submit text/* to this server, not "
                                      , contentTypeT
                                      , "\r\n" ]
    enc <- maybe (Left $ do status badRequest400
                            text $ mconcat [ "Unknown charset "
                                           , charset
                                           , "\r\n" ])
                 Right
                 $ encodingFromStringExplicit $ unpack charset
    case decodeLazyByteStringExplicit enc bs of
        Left e -> Left $ do status badRequest400
                            text $ mconcat [ "Character encoding error: "
                                           , pack $ show e
                                           , "\r\n" ]
        Right txt -> return
            $ replace "\r\n" "\n"   -- internet newlines to Haskell newlines
            $ pack txt
    where contentTypeT = -- default per RFC 2616 section 7.2.1
                         fromMaybe "application/octet-stream" maybeContentType
          contentType = parseContentType $ toStrict contentTypeT
          charset = contentType
                  <&> mimeParams
                  <&> map (\x -> ( toLower . fromStrict . paramName $ x
                                 , paramValue x))
                  >>= lookup "charset"
                  & fromMaybe "iso-8859-1"  -- default per RFC 2616 section 3.7.1
                  & fromStrict

maybeRead :: (Read a) => String -> Maybe a
maybeRead s = do
    (a,unparsed) <- listToMaybe $ reads s
    if unparsed == "" then Just a else Nothing

usage :: String -> String
usage progname = "usage: " ++ progname ++ " port filename\n\
                 \       " ++ progname ++ " --version"

data Action = RunServer Port FilePath
            | ShowVersion

parseArgs :: String -> [String] -> Either String Action
parseArgs _ [verflag]
    | verflag == "--version" = Right ShowVersion
parseArgs _ [port,filename] =
    case maybeRead port of
        Nothing ->
            Left $ "error: cannot interpret " ++ port ++ " as an integer"
        Just n ->
            Right $ RunServer n filename
parseArgs progname _ = Left $ usage progname

-- The following are from Control.Lens.Combinators
infixl 1 &, <&>
(&) :: a -> (a->b) -> b
a & f = f a
{-# INLINE (&) #-}
(<&>) :: (Functor f) => f a -> (a->b) -> f b
as <&> f = fmap f as
{-# INLINE (<&>) #-}
