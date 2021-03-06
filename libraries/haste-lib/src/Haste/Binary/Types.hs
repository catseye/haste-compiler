{-# LANGUAGE CPP, GeneralizedNewtypeDeriving, OverloadedStrings #-}
module Haste.Binary.Types (
    Ix, ArrView, Blob (..), BlobData (..),
    blobSize, blobDataSize, toByteString, fromByteString, toBlob, strToBlob,
    toUArray, fromUArray
  ) where
import Haste.Prim
import Haste.Prim.Foreign
import Haste.Foreign.Array
import qualified Data.ByteString.Lazy as BS
import Data.Array.Unboxed
#ifndef __HASTE__
import qualified Data.ByteString.UTF8 as BU
#else
import System.IO.Unsafe
#endif

#ifdef __HASTE__
-- | In a browser context, BlobData is essentially a DataView, with an
--   accompanying offset and length for fast slicing.
--   In a server context, it is simply a 'BS.ByteString'.
data BlobData = BlobData Int Int JSAny

-- | A JavaScript Blob on the client, a 'BS.ByteString' on the server.
newtype Blob = Blob JSAny deriving (ToAny, FromAny)

-- | The size, in bytes, of the contents of the given blob.
blobSize :: Blob -> Int
blobSize = unsafePerformIO . ffi "(function(b){return b.size;})"

-- | The size, in bytes, of the contents of the given blob data.
blobDataSize :: BlobData -> Int
blobDataSize (BlobData _ len _) = len

-- | Convert a 'BlobData' to an unboxed array; client-side only.
toUArray :: (Ix i, ArrView e) => BlobData -> UArray i e
toUArray (BlobData from to buf) = unsafePerformIO $ toUArray' from to buf

-- | Convert a an unboxed array into a 'Blob'; client-side only.
fromUArray :: (Ix i, ArrView e) => UArray i e -> Blob
fromUArray = unsafePerformIO . fromUArray'

fromUArray' :: (Ix i, ArrView e) => UArray i e -> IO Blob
fromUArray' = ffi "(function(arr){return new Blob([arr]);})"

toUArray' :: (Ix i, ArrView e) => Int -> Int -> JSAny -> IO (UArray i e)
toUArray' = ffi "(function(from, to, buf){return new Uint8Array(buf.buffer.slice(from, to+from));})"

-- | Convert a BlobData to a ByteString. Only usable server-side.
toByteString :: BlobData -> BS.ByteString
toByteString =
  error "Haste.Binary.Types.toByteString called in browser context!"

-- | Convert a ByteString to a BlobData. Only usable server-side.
fromByteString :: BS.ByteString -> BlobData
fromByteString =
  error "Haste.Binary.Types.toByteString called in browser context!"

-- | Convert a piece of BlobData back into a Blob.
toBlob :: BlobData -> Blob
toBlob (BlobData 0 len buf) =
  case newBlob buf of
    b | blobSize b > len -> sliceBlob b 0 len
      | otherwise        -> b
toBlob (BlobData off len buf) =
  sliceBlob (newBlob buf) off (off+len)

-- | Create a Blob from a JSString.
strToBlob :: JSString -> Blob
strToBlob = newBlob . toAny

sliceBlob :: Blob -> Int -> Int -> Blob
sliceBlob b off len = unsafePerformIO $ jsSlice b off len

jsSlice :: Blob -> Int -> Int -> IO Blob
jsSlice = ffi "(function(b,off,len){return b.slice(off,len);})"

newBlob :: JSAny -> Blob
newBlob = unsafePerformIO . jsNewBlob

jsNewBlob :: JSAny -> IO Blob
jsNewBlob =
  ffi "(function(b){try {return new Blob([b]);} catch (e) {return new Blob([b.buffer]);}})"
#else

-- | In a browser context, BlobData is essentially a DataView, with an
--   accompanying offset and length for fast slicing.
--   In a server context, it is simply a 'BS.ByteString'.
newtype BlobData = BlobData BS.ByteString

-- | A JavaScript Blob on the client, a 'BS.ByteString' on the server.
newtype Blob = Blob BS.ByteString

-- Never used except for type checking
clientOnly :: a
clientOnly = error "ToAny/FromAny only usable client-side!"
instance ToAny BlobData where toAny = clientOnly
instance FromAny BlobData where fromAny = clientOnly
instance ToAny Blob where toAny = clientOnly
instance FromAny Blob where fromAny = clientOnly

-- | Convert a 'BlobData' to an unboxed array; client-side only.
toUArray :: (Ix i, ArrView e) => BlobData -> UArray i e
toUArray _ = error "toUArray only usable client-side!"

-- | Convert a an unboxed array into a 'Blob'; client-side only.
fromUArray :: (Ix i, ArrView e) => UArray i e -> Blob
fromUArray = error "fromUArray only usable client-side!"

-- | The size, in bytes, of the contents of the given blob.
blobSize :: Blob -> Int
blobSize (Blob b) = fromIntegral $ BS.length b

-- | The size, in bytes, of the contents of the given blob data.
blobDataSize :: BlobData -> Int
blobDataSize (BlobData bd) = fromIntegral $ BS.length bd

-- | Convert a BlobData to a ByteString. Only usable server-side.
toByteString :: BlobData -> BS.ByteString
toByteString (BlobData bd) = bd

-- | Convert a ByteString to a BlobData. Only usable server-side.
fromByteString :: BS.ByteString -> BlobData
fromByteString = BlobData

-- | Convert a piece of BlobData back into a Blob.
toBlob :: BlobData -> Blob
toBlob (BlobData bs) = Blob bs

-- | Create a Blob from a JSString.
strToBlob :: JSString -> Blob
strToBlob s = Blob $ BS.fromChunks [BU.fromString $ fromJSStr s]

#endif
