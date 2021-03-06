
module Examples.Util(module Examples.Util) where

import Development.Shake
import Development.Shake.FilePath

import Control.Concurrent
import Control.Monad
import Data.List
import System.Directory as IO
import System.Environment
import System.Random
import System.Console.GetOpt


shaken
    :: (([String] -> IO ()) -> (String -> String) -> IO ())
    -> ([String] -> (String -> String) -> Rules ())
    -> IO ()
    -> IO ()
shaken test rules sleeper = do
    name:args <- getArgs
    when ("--sleep" `elem` args) sleeper
    putStrLn $ "## BUILD " ++ unwords (name:args)
    args <- return $ delete "--sleep" args
    let out = "output/" ++ name ++ "/"
    createDirectoryIfMissing True out
    case args of
        "test":extra -> do
            putStrLn $ "## TESTING " ++ name
            -- if the extra arguments are not --quiet/--loud it's probably going to go wrong
            let obj x = if "/" `isPrefixOf` x then init out ++ x else out ++ x
            test (\args -> withArgs (name:args ++ extra) $ shaken test rules sleeper) obj
            putStrLn $ "## FINISHED TESTING " ++ name
        "clean":_ -> removeDirectoryRecursive out
{-
        "lint":args -> do
            let dbfile = out ++ ".database"
                tempfile = "output/" ++ name ++ ".database"
            b <- IO.doesFileExist dbfile
            when b $ renameFile dbfile tempfile
            removeDirectoryRecursive out
            createDirectoryIfMissing True out
            when b $ renameFile tempfile dbfile
            shake shakeOptions{shakeFiles=out, shakeLint=True} $ rules args (out++)
-}

        "perturb":args -> forever $ do
            del <- removeFilesRandom out
            threads <- randomRIO (1,4)
            putStrLn $ "## TESTING PERTURBATION (" ++ show del ++ " files, " ++ show threads ++ " threads)"
            shake shakeOptions{shakeFiles=out, shakeThreads=threads, shakeVerbosity=Quiet} $ rules args (out++)

        args -> do
            let (_,files,_) = getOpt Permute [] args
            withArgs (args \\ files) $
                shakeWithClean
                    (removeDirectoryRecursive out) 
                    (shakeOptions{shakeFiles=out, shakeReport=Just $ "output/" ++ name ++ "/report.html", shakeLint=True})
                    (rules files (out++))


shakeWithClean :: IO () -> ShakeOptions -> Rules () -> IO ()
shakeWithClean clean opts rules = shakeArgsWith opts [cleanOpt] f
    where
        cleanOpt = Option "c" ["clean"] (NoArg $ Right ()) "Clean before building."

        f extra files = do
            when (extra /= []) clean
            if "clean" `elem` files then
                clean >> return Nothing
             else
                return $ Just $ if null files then rules else want files >> withoutActions rules


unobj :: FilePath -> FilePath
unobj = dropDirectory1 . dropDirectory1

assert :: Bool -> String -> IO ()
assert b msg = unless b $ error $ "ASSERTION FAILED: " ++ msg

infix 4 ===

(===) :: (Show a, Eq a) => a -> a -> IO ()
a === b = assert (a == b) $ "failed in ===\nLHS: " ++ show a ++ "\nRHS: " ++ show b


assertContents :: FilePath -> String -> IO ()
assertContents file want = do
    got <- readFile file
    assert (want == got) $ "File contents are wrong: " ++ file ++ "\nWANT: " ++ want ++ "\nGOT: " ++ got


noTest :: ([String] -> IO ()) -> (String -> String) -> IO ()
noTest build obj = do
    build ["--abbrev=output=$OUT"]
    build []


sleep :: Double -> IO ()
sleep x = threadDelay $ ceiling $ x * 1000000


-- | Sleep long enough for the modification time resolution to catch up
sleepFileTime :: IO ()
sleepFileTime = sleep 1


removeFilesRandom :: FilePath -> IO Int
removeFilesRandom x = do
    files <- getDirectoryContentsRecursive x
    n <- randomRIO (0,length files)
    rs <- replicateM (length files) (randomIO :: IO Double)
    mapM_ (removeFile . snd) $ sort $ zip rs files
    return n


getDirectoryContentsRecursive :: FilePath -> IO [FilePath]
getDirectoryContentsRecursive dir = do
    xs <- IO.getDirectoryContents dir
    (dirs,files) <- partitionM IO.doesDirectoryExist [dir </> x | x <- xs, not $ isBadDir x]
    rest <- concatMapM getDirectoryContentsRecursive dirs
    return $ files++rest
    where
        isBadDir x = "." `isPrefixOf` x || "_" `isPrefixOf` x

partitionM :: Monad m => (a -> m Bool) -> [a] -> m ([a], [a])
partitionM f [] = return ([], [])
partitionM f (x:xs) = do
    res <- f x
    (as,bs) <- partitionM f xs
    return $ if res then (x:as,bs) else (as,x:bs)

concatMapM :: Monad m => (a -> m [b]) -> [a] -> m [b]
concatMapM f = liftM concat . mapM f

