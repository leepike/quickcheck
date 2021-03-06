-- | A wrapper around the system random number generator. Internal QuickCheck module.
{-# LANGUAGE CPP #-}
module Test.QuickCheck.Random where

#ifndef NO_TF_RANDOM
import System.Random
import System.Random.TF hiding (split, next)
import Data.Word
import Data.Bits

#define TheGen TFGen

newTheGen :: IO TFGen
newTheGen = fmap seedTFGen mkSeedTime

bits, mask, doneBit :: Integral a => a
bits = 14
mask = 0x3fff
doneBit = 0x4000

chip :: Bool -> Word32 -> TFGen -> TFGen
chip done n g = splitn g (bits+1) (if done then m .|. doneBit else m)
  where
    m = n .&. mask

chop :: Integer -> Integer
chop n = n `shiftR` bits

stop :: Integral a => a -> Bool
stop n = n <= mask

mkTheGen :: Int -> TFGen
mkTheGen n = seedTFGen (fromIntegral n, 0, 0, 0)

#else
import System.Random

#define TheGen StdGen

newTheGen :: IO StdGen
newTheGen = newStdGen

mkTheGen :: Int -> StdGen
mkTheGen = mkStdGen

chip :: Bool -> Int -> StdGen -> StdGen
chip finished n = boolVariant finished . boolVariant (even n)

chop :: Integer -> Integer
chop n = n `div` 2

stop :: Integral a => a -> Bool
stop n = n <= 1
#endif

-- | The "standard" QuickCheck random number generator.
-- A wrapper around either 'TFGen' on GHC, or 'StdGen'
-- on other Haskell systems.
newtype QCGen = QCGen TheGen

instance Show QCGen where
  showsPrec n (QCGen g) = showsPrec n g
instance Read QCGen where
  readsPrec n xs = [(QCGen g, ys) | (g, ys) <- readsPrec n xs]

instance RandomGen QCGen where
  split (QCGen g) = (QCGen g1, QCGen g2)
    where
      (g1, g2) = split g
  genRange (QCGen g) = genRange g
  next (QCGen g) = (x, QCGen g')
    where
      (x, g') = next g

newQCGen :: IO QCGen
newQCGen = fmap QCGen newTheGen

mkQCGen :: Int -> QCGen
mkQCGen n = QCGen (mkTheGen n)

bigNatVariant :: Integer -> TheGen -> TheGen
bigNatVariant n g
  | g `seq` stop n = chip True (fromInteger n) g
  | otherwise      = (bigNatVariant $! chop n) $! chip False (fromInteger n) g

{-# INLINE natVariant #-}
natVariant :: Integral a => a -> TheGen -> TheGen
natVariant n g
  | g `seq` stop n = chip True (fromIntegral n) g
  | otherwise      = bigNatVariant (toInteger n) g

{-# INLINE variantTheGen #-}
variantTheGen :: Integral a => a -> TheGen -> TheGen
variantTheGen n g
  | n >= 1    = natVariant (n-1) (boolVariant False g)
  | n == 0   = natVariant (0 `asTypeOf` n) (boolVariant True g)
  | otherwise = bigNatVariant (negate (toInteger n)) (boolVariant True g)

boolVariant :: Bool -> TheGen -> TheGen
boolVariant False = fst . split
boolVariant True = snd . split

variantQCGen :: Integral a => a -> QCGen -> QCGen
variantQCGen n (QCGen g) = QCGen (variantTheGen n g)
