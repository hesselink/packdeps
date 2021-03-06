{-# LANGUAGE QuasiQuotes, TypeFamilies, OverloadedStrings #-}
import Yesod
import Yesod.Helpers.AtomFeed
import Distribution.PackDeps
import Data.Maybe
import Data.List (sortBy)
import Data.Ord (comparing)
import Data.Time
import Distribution.Package
import Distribution.Text
import Control.Arrow

data PD = PD Newest
type Handler = GHandler PD PD
mkYesod "PD" [$parseRoutes|
/ RootR GET
/feed FeedR GET
/feed/#String Feed2R GET
/feed/#String/#String/#String/#String Feed3R GET
/specific SpecificR GET
/feed/specific/#String SpecificFeedR GET
|]
instance Yesod PD where approot _ = ""

getRootR = defaultLayout $ do
    setTitle "Hackage dependency monitor"
    addCassius [$cassius|
body
    font-family: Arial,Helvetica,sans-serif
    width: 600px
    margin: 2em auto
    text-align: center
p
    text-align: justify
h2
    border-bottom: 2px solid #999
input[type=text]
    width: 400px
#footer
    margin-top: 15px
    border-top: 1px dashed #999
    padding-top: 10px
|]
    [$hamlet|
%h1 Hackage Dependency Monitor
%form!action=@FeedR@
    %input!type=text!name=needle!required!placeholder="Search string"
    %input!type=submit!value=Check
%h2 What is this?
%p It can often get tedious to keep your package dependencies up-to-date. This tool is meant to alleviate a lot of the burden. It will automatically determine when an upper bound on a package prevents the usage of a newer version. For example, if foo depends on bar &gt;= 0.1 &amp;&amp; &lt; 0.2, and bar 0.2 exists, this tool will flag it.
%p Enter a search string in the box above. It will find all packages containing that string in the package name, maintainer or author fields, and create an Atom feed for restrictive bounds. Simply add that URL to a news reader, and you're good to go!
%p
    All of the code is $
    %a!href="http://github.com/snoyberg/packdeps" available on Github
    \. Most likely in the near future I'll also publish an executable on Hackage which will let you do this check against non-published packages.
#footer
    %a!href="http://docs.yesodweb.com/" Powered by Yesod
|]

getDeps needle = do
    PD newest <- getYesod
    let descs = filterPackages needle newest
        go (_, _, AllNewest) = Nothing
        go (PackageName x, v, WontAccept y z) = Just ((x, v), (y, z))
        deps = reverse $ sortBy (comparing $ snd . snd)
             $ mapMaybe (go . checkDeps newest) descs
    return deps

getFeedR :: Handler RepHtml
getFeedR = do
    needle <- runFormGet' $ stringInput "needle"
    deps <- getDeps needle
    let title = "Newer dependencies for " ++ needle
    defaultLayout $ do
        setTitle $ string title
        addCassius [$cassius|
body
    font-family: Arial,Helvetica,sans-serif
    width: 600px
    margin: 2em auto
h1
    text-align: center
p
    text-align: justify
table
    border-collapse: collapse
th, td
    border: 1px solid #999
    padding: 5px
h3
    margin: 20px 0 5px 0
|]
        let feedR = Feed2R needle
        atomLink feedR title
        [$hamlet|
%h1 $title$
%p
    The following are the packages which have restrictive upper bounds. You can also $
    %a!href=@feedR@ view this information as a news feed
    \ so you can get automatic updates in your feed reader of choice.
$if null.deps
    %p
        %b All upper bounds are non-restrictive.
$else
    $forall deps d
        %h3 $fst.fst.d$-$display.snd.fst.d$
        %table
            $forall fst.snd.d p
                %tr
                    %th $fst.p$
                    %td $snd.p$
|]

getFeed2R needle = do
    deps <- getDeps needle
    now <- liftIO getCurrentTime
    atomFeed AtomFeed
        { atomTitle = "Newer dependencies for " ++ needle
        , atomLinkSelf = Feed2R needle
        , atomLinkHome = RootR
        , atomUpdated = now
        , atomEntries = map go' deps
        }
  where
    go' ((name, version), (deps, time)) = AtomFeedEntry
        { atomEntryLink = Feed3R needle name (display version) (show time)
        , atomEntryUpdated = time
        , atomEntryTitle = "Outdated dependencies for " ++ name ++ " " ++ display version
        , atomEntryContent = [$hamlet|
%table!border=1
    $forall deps d
        %tr
            %th $fst.d$
            %td $snd.d$
|]
        }

getFeed3R :: String -> String -> String -> String -> Handler ()
getFeed3R _ package _ _ =
    redirectString RedirectPermanent
  $ "http://hackage.haskell.org/cgi-bin/hackage-scripts/package/" ++ package

main = do
    newest <- read `fmap` readFile "newest"
    basicHandler 3000 $ PD newest

getSpecificR :: Handler RepHtml
getSpecificR = do
    packages' <- lookupGetParams "package"
    PD newest <- getYesod
    let packages = map (id &&& flip getPackage newest) packages'
    let title = "Newer dependencies for your Hackage packages"
    let checkDeps' x =
            case checkDeps newest x of
                (_, _, AllNewest) -> Nothing
                (_, v, WontAccept cd _) -> Just (v, cd)
    defaultLayout $ do
        setTitle $ string title
        addCassius [$cassius|
body
    font-family: Arial,Helvetica,sans-serif
    width: 600px
    margin: 2em auto
h1
    text-align: center
p
    text-align: justify
table
    border-collapse: collapse
th, td
    border: 1px solid #999
    padding: 5px
h3
    margin: 20px 0 5px 0
|]
        let feedR = SpecificFeedR $ unwords packages'
        atomLink feedR title
        [$hamlet|
%h1 $title$
%p
    The following are the packages which have restrictive upper bounds. You can also $
    %a!href=@feedR@ view this information as a news feed
    \ so you can get automatic updates in your feed reader of choice.
$forall packages p
    $maybe snd.p descinfo
        $maybe checkDeps'.descinfo x
            %h3 $fst.p$-$display.fst.x$
            %table
                $forall snd.x p
                    %tr
                        %th $fst.p$
                        %td $snd.p$
        $nothing
            %h3 $fst.p$ up to date
    $nothing
        %p Invalid package name: $fst.p$
|]

getSpecificFeedR packages' = do
    PD newest <- getYesod
    let descs = mapMaybe (flip getPackage newest) $ words packages'
    let go (_, _, AllNewest) = Nothing
        go (PackageName x, v, WontAccept y z) = Just ((x, v), (y, z))
        deps = reverse $ sortBy (comparing $ snd . snd)
             $ mapMaybe (go . checkDeps newest) descs
    now <- liftIO getCurrentTime
    atomFeed AtomFeed
        { atomTitle = "Newer dependencies for Hackage packages"
        , atomLinkSelf = SpecificFeedR packages'
        , atomLinkHome = RootR
        , atomUpdated = now
        , atomEntries = map go' deps
        }
  where
    go' ((name, version), (deps, time)) = AtomFeedEntry
        { atomEntryLink = Feed3R packages' name (display version) (show time)
        , atomEntryUpdated = time
        , atomEntryTitle = "Outdated dependencies for " ++ name ++ " " ++ display version
        , atomEntryContent = [$hamlet|
%table!border=1
    $forall deps d
        %tr
            %th $fst.d$
            %td $snd.d$
|]
        }
