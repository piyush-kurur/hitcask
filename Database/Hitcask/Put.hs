module Database.Hitcask.Put where
import Database.Hitcask.Types
import Database.Hitcask.Timestamp
import Data.ByteString(ByteString)
import qualified Data.ByteString.Char8 as B
import Control.Concurrent.STM
import System.IO
import qualified Data.HashMap.Strict as M
import Data.Serialize.Put
import Data.Digest.CRC32

put :: Hitcask -> Key -> Value -> IO Hitcask
put h key value = do
  f <- getHandle h
  hSeek f SeekFromEnd 0
  currentPosition <- hTell f
  time <- currentTimestamp
  c <- readTVarIO $ current h
  let valueLocation = formatValue (path c) value currentPosition time
  b <- updateKeyDir h key valueLocation
  appendToLog f key value valueLocation
  return $! b

updateKeyDir :: Hitcask -> Key -> ValueLocation -> IO Hitcask
updateKeyDir h key valueLocation = atomically $ do
    modifyTVar' (keys h) $ \m ->
      M.insert key valueLocation m
    return $! h

formatValue :: FilePath -> Value -> Integer -> Integer -> ValueLocation
formatValue filePath value = ValueLocation filePath (B.length value)

appendToLog :: Handle -> Key -> Value -> ValueLocation -> IO ()
appendToLog h key value (ValueLocation _ _ _ t) = B.hPut h (formatForLog key value t)

putInt32 ::  Integral a => a -> Put
putInt32 a = putWord32be $ fromIntegral a

type LogEntry = ByteString
formatForLog :: Key -> Value -> Integer -> LogEntry
formatForLog k v t = runPut $ do
  putWord32be $ crc32 v
  putInt32 t
  putInt32 $ B.length k
  putInt32 $ B.length v
  putByteString k
  putByteString v

