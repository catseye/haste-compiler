{-# LANGUAGE OverloadedStrings, TypeFamilies, GeneralizedNewtypeDeriving #-}
-- | Events relating to mouse keyboard input.
module Haste.Events.MessageEvents
  ( MessageEvent (..) , MessageData (..), Window
  , postMessage, getContentWindow, window, fromAny
  ) where
import Control.Monad.IO.Class
import Haste.JSString (JSString)
import Haste.Prim.Foreign
import Haste.Events.Core
import Haste.DOM.Core (IsElem (..), Elem (..))

-- | A DOM window.
newtype Window = Window JSAny
  deriving (ToAny, FromAny, Eq)

instance IsElem Window where
  elemOf (Window e) = Elem e
  fromElem = getContentWindow'

-- | The window in which the program is executing.
window :: Window
window = constant "window"

-- | Event data for keyboard events.
data MessageData = MessageData
  { messageData   :: !JSAny
  , messageOrigin :: !JSString
  , messageSource :: !Window
  }

data MessageEvent = Message

instance Event MessageEvent where
  type EventData MessageEvent = MessageData
  eventName Message = "message"
  eventData _ e =
    MessageData <$> get e "data"
                <*> get e "origin"
                <*> get e "source"

-- | Post a message to the given window. Messages are serialized using the
--   structured clone algorithm, meaning that you can post pretty much any
--   type of data, except functions, references and the like.
postMessage :: (ToAny a, MonadIO m) => Window -> a -> m ()
postMessage wnd msg = liftIO $ postMessage' wnd (toAny msg)

postMessage' :: Window -> JSAny -> IO ()
postMessage' = ffi "(function(w,m){w.postMessage(m,'*');})"

-- | Get the window object for an iframe. Must be called after the iframe is
--   attached to the DOM.
getContentWindow :: MonadIO m => Elem -> m (Maybe Window)
getContentWindow e = liftIO $ getContentWindow' e

getContentWindow' :: Elem -> IO (Maybe Window)
getContentWindow' = ffi "(function(e)){return e.contentWindow;}"
