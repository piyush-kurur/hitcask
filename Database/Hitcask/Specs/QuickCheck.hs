{-# OPTIONS_GHC -fno-warn-orphans #-}
module Database.Hitcask.Specs.QuickCheck where
import Database.Hitcask.Types
import Database.Hitcask.SpecHelper
import Database.Hitcask
import Database.Hitcask.Specs.Arbitrary
import qualified Data.HashMap.Strict as M
import Control.Monad
import Test.QuickCheck.Monadic
import Test.QuickCheck
import Data.Maybe
import Debug.Trace

instance Arbitrary HitcaskAction where
  arbitrary = do
    (NonEmptyKey k) <- arbitrary
    (NonEmptyValue v) <- arbitrary
    elements [Put k v, Delete k, Merge, CloseAndReopen]

data HitcaskAction =
    Put Key Value
  | Delete Key
  | Merge
  | CloseAndReopen
  deriving(Show, Eq)

data HitcaskPostCondition =
    KeyHasValue Key Value
  | KeyIsEmpty Key
  deriving(Show, Eq)

newtype MaxBytes = MaxBytes Integer deriving(Show)

instance Arbitrary MaxBytes where
  arbitrary = do
    (Positive x) <- arbitrary
    return $! MaxBytes x

propCheckPostConditions :: (HitcaskFilePath, MaxBytes) -> [HitcaskAction] -> Property
propCheckPostConditions (HitcaskFilePath fp, MaxBytes b) actions = monadicIO $ do
  db <- run $ createEmptyWith fp (standardSettings { maxBytes = b})
  let postConditions = postConditionsFromActions actions
  db2 <- run $ runActions db actions
  checkPostConditions db2 postConditions
  run $ closeDB db2

type PostConditions = M.HashMap Key HitcaskPostCondition

postConditionsFromActions :: [HitcaskAction] -> PostConditions
postConditionsFromActions = M.fromList . concatMap postcondition

postcondition :: HitcaskAction -> [(Key, HitcaskPostCondition)]
postcondition (Put k v) = [(k, KeyHasValue k v)]
postcondition (Delete k) = [(k, KeyIsEmpty k)]
postcondition Merge = []
postcondition CloseAndReopen = []

runActions :: Hitcask -> [HitcaskAction] -> IO Hitcask
runActions = foldM runAction

runAction :: Hitcask -> HitcaskAction -> IO Hitcask
runAction db (Put k v) = do
  put db k v
  return db
runAction db (Delete k) = do
 delete db k
 return db
runAction db Merge = do
  compact db
  return db
runAction db CloseAndReopen = do
  close db
  connect (dirPath db)

checkPostConditions :: Hitcask -> PostConditions -> PropertyM IO ()
checkPostConditions db ps = do
  let ks = M.elems ps
  checked <- run $ mapM (checkWithGoodError db) ks
  assert $ and checked

checkWithGoodError :: Hitcask -> HitcaskPostCondition -> IO Bool
checkWithGoodError db c = do
  s <- checkCondition db c
  unless s $
    trace (show c ++ "\n") $ return ()
  return s

instance Show HitcaskFilePath where
  show (HitcaskFilePath fp) = fp

checkCondition :: Hitcask -> HitcaskPostCondition -> IO Bool
checkCondition db (KeyHasValue k v) = do
  j <- get db k
  return $! j == Just v
checkCondition db (KeyIsEmpty k) = do
  n <- get db k
  return $! isNothing n

