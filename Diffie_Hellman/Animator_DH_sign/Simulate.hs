{- generated by Isabelle -}

module Simulate (simulate) where
import Interaction_Trees;
import Prelude;
import Text.Read;
import Text.Show.Pretty;
-- import Partial_Fun;
import System.IO;
import DH_message;
import qualified Data.List (dropWhile, dropWhileEnd, intersect, head, tail, elemIndex, uncons);
import Control.Monad (forM_, when);
import System.Exit (exitWith, ExitCode( ExitSuccess ));
-- import System.Random
import System.Random.Stateful;
import Data.Char (isSpace); 

splitWhen :: (Char -> Bool) -> String -> [String]
splitWhen p s =  case Data.List.dropWhile p s of
   "" -> []
   s' -> w : splitWhen p s''
         where (w, s'') = break p s'

splitOn c = splitWhen (== c)

deleteWhen             :: (a -> Bool) -> [a] -> [a]
deleteWhen _  []       = []
deleteWhen p (y:ys)    = if p y then ys else y : deleteWhen p ys

deleteBy                :: (a -> a -> Bool) -> a -> [a] -> [a]
deleteBy _  _ []        = []
deleteBy eq x (y:ys)    = if x `eq` y then ys else y : deleteBy eq x ys

-- It is not ideal to use this way [show event (prelude.show Chan)=> parse textual event (use read) => pattern match Chan] to pretty print channels
-- But I haven't figured out a way to customise show for Chan without removing 'Prelude.Show' in Chan's definition because it is automatically generated by Isabelle/HOL
--    deriving (Prelude.Read, Prelude.Show);
data ForPrint = FP String;

-- instance Show a => Show (ForPrint a) where 
--   show (FP x) = case (readMaybe x) of
--     Just (Env_C a)   -> "Env"
--     _           -> "Others"

printFP :: ForPrint -> String;
printFP (FP x) = case (read x) of 
  (Env_C (a, b)) -> "Env [" ++ Prelude.show a ++ "] " ++ Prelude.show b;
  (Send_C (a, (b, c))) -> "Send [" ++ Prelude.show a ++ "=>" ++ Prelude.show b ++ "] " ++ ppChan c;
  (Recv_C (a, (b, c))) -> "Recv [" ++ Prelude.show b ++ "<=" ++ Prelude.show a ++ "] " ++ ppChan c;
  (Hear_C (a, (b, c))) -> "Hear [" ++ Prelude.show b ++ "<=" ++ Prelude.show a ++ "] " ++ ppChan c;
  (Fake_C (a, (b, c))) -> "Fake [" ++ Prelude.show b ++ "=>" ++ Prelude.show a ++ "] " ++ ppChan c;
  (Leak_C d) -> "Leak " ++ ppChan d ;
  (Sig_C d) -> "Sig " ++ ppShow d ;
  (Terminate_C _) -> "Terminate";

ppChan :: Dmsg -> String
ppChan (MAg a) = ppShow a; 
ppChan (MNon n) = ppShow n;
ppChan (MKp p) = ppShow p;
ppChan (MKs s) = ppShow s;
ppChan (MCmp m1 m2) = "<" ++ ppChan m1 ++ ", " ++ ppChan m2 ++ ">";
ppChan (MEnc m k) = ['{'] ++ ppChan m ++ ['}'] ++ "_" ++ ppShow k;
ppChan (MSig m k) = ['{'] ++ ppChan m ++ ['}'] ++ "^s_" ++ ppShow k;
ppChan (MSEnc m k) = ['{'] ++ ppChan m ++ ['}'] ++ "^S_" ++ ppChan k;
ppChan (MExpg) = "g";
ppChan (MModExp m e) = ppChan m ++ ['^'] ++ ppShow e;


data AutoCmd = Auto Int 
  | Rand Int 
  | AReach Int -- Chan -- check reachability of Event
  | RReach Int -- Chan -- check reachability of Event
  | Quit 
  | Manual 
  | Deadlock 
  | Feasible 
  deriving (Prelude.Read, Prelude.Show);

-- These library functions help us to trim the "_C" strings from pretty printed events

isPrefixOf              :: (Eq a) => [a] -> [a] -> Bool;
isPrefixOf [] _         =  True;
isPrefixOf _  []        =  False;
isPrefixOf (x:xs) (y:ys)=  x == y && isPrefixOf xs ys;

removeSubstr :: String -> String -> String;
removeSubstr w "" = "";
removeSubstr w s@(c:cs) = (if w `isPrefixOf` s then Prelude.drop (Prelude.length w) s else c : removeSubstr w cs);

showTrace :: (Prelude.Show e) => [e] -> String
showTrace [] = "" 
showTrace (t:ts) = (printFP (FP (Prelude.show t))) ++ ", " ++ showTrace ts;

ppTrace e = "[" ++ showTrace e ++ "]"

-- %er1;er2;...%
format_events :: String -> [String]
format_events ins = let
    r1 = deleteBy (==) '%' ins;
    r2 = deleteBy (==) '%' r1;
    rl = splitOn ';' r2;
    rl1 = map (Data.List.dropWhile (isSpace)) rl;
    rl2 = map (Data.List.dropWhileEnd (isSpace)) rl1
  in rl2 

-- %er1;er2;...% # %em1;em2;...%
-- a list of events for reachability check and a list events for monitor only (so our search won't stop when encountering a monitor event)
format_reach :: String -> ([String], [String])
format_reach ins = 
  let rm = splitOn '#' ins
  in case Data.List.uncons rm of
    Nothing -> ([], []) 
    Just (re, tl) -> case Data.List.uncons tl of
      Nothing -> (format_events re, []) 
      Just (me, tl) -> (format_events re, format_events me)

{- simulate_cnt n P mod steps re me tr
  n: the maximum number of steps that internal events should be executed
  P: the process for animation
  mod: current automation mode
  steps: current no. of steps in automation 
  re: events for reachability check
  me: events for monitor 
  tr: the current trace 
-}
simulate_cnt :: (Eq e, Prelude.Show e, Prelude.Read e, Prelude.Show s) => Prelude.Int -> Itree e s -> AutoCmd -> Prelude.Int -> [String] -> [String] -> [e] -> Prelude.IO ();
simulate_cnt n (Ret x) mod steps re me tr = case mod of
  (AReach _) -> Prelude.putStr ""
  (RReach _) -> Prelude.putStr ""
  _ -> do {
  Prelude.putStrLn ("Successfully Terminated: " ++ Prelude.show x);
  Prelude.putStrLn ("Trace: " ++ (ppTrace tr)) 
}
simulate_cnt n (Sil p) mod steps re me tr = 
  do { --if (n == 0) then Prelude.putStrLn "Internal Activity..." else return ();
       if (n >= 2000) then do { 
         Prelude.putStr "Many steps (> 2000); Continue? [Y/N]"; 
         q <- Prelude.getLine; 
         if (q == "Y") then simulate_cnt 0 p mod steps re me tr else Prelude.putStrLn "Ended early.";
                            }
       else simulate_cnt (n + 1) p mod steps re me tr 
 }

simulate_cnt n (Vis (Pfun_of_alist [])) mod steps re me tr = case mod of
  (AReach _) -> Prelude.putStr "."
  (RReach _) -> Prelude.putStr "."
  _ -> do {
  Prelude.putStrLn "*** Deadlocked ***";
  Prelude.putStrLn ("Trace: " ++ (ppTrace tr)) 
}

simulate_cnt n t@(Vis (Pfun_of_alist m)) mod steps re me tr = 
  do { 
      let 
        -- All available visible events, as string
        events = (map (\m -> printFP (FP (Prelude.show (fst m)))) m);
      in 
        do {
          case mod of
            (Auto x) -> if steps >= x then 
            -- switch to manual after specified steps
                do {
                  -- simulate_cnt n t Manual 0 tr
                  -- Prelude.putStrLn ("Auto [" ++ (show x) ++ "] Trace: " ++ (ppTrace tr)) 
                  -- return ()
                  Prelude.putStr ("-")
                } 
              else 
                do {
                  forM_ m $ \s -> simulate_cnt n (snd s) mod (steps+1) re me (tr ++ [fst s]) ;
                  when (steps == 0) (  Prelude.putStrLn ("*** Auto [" ++ (show x) ++ "] Finished ***") )
                  -- if (steps == 0) then 
                  --   do { Prelude.putStrLn ("*** Auto [" ++ (show x) ++ "] Finished ***") }
                  -- else
                  --   do { }
                }
            (Rand x) -> if steps >= x then 
            -- switch to manual after specified steps
                do {
                  -- simulate_cnt n t Manual 0 tr
                  -- Prelude.putStrLn ("Rand [" ++ (show x) ++ "] Trace: " ++ (ppTrace tr)) 
                  -- return ()
                  Prelude.putStr ("-")
                } 
              else 
                do {
                  -- if there is only one event, we don't need to choose
                  if (Prelude.length m == 1) 
                  then do { 
                    -- Prelude.putStrLn ("Random: only 1" ++ "> " ++  (Prelude.show (fst (m !! (0))))) ; 
                    simulate_cnt 0 (snd (m !! (0))) mod (steps + 1) re me (tr ++ [fst (m !! (0))]) 
                    }
                  else
                    do {
                      rn <- applyAtomicGen (uniformR (1 :: Int, Prelude.length m)) globalStdGen;
                      -- let (rn, newg) = uniformR (1 :: Int, Prelude.length m)
                      -- in 
                      do { 
                        -- Prelude.putStrLn ("Random chosen: " ++ show rn ++ "> " ++ (Prelude.show (fst (m !! (rn-1))))) ; 
                        simulate_cnt 0 (snd (m !! (rn-1))) mod (steps + 1) re me (tr ++ [fst (m !! (rn-1))])
                      }
                    }
                  ;
                  when (steps == 0) (  Prelude.putStrLn ("*** Random [" ++ (show x) ++ "] Finished ***") )
                }
            (AReach x) -> if steps >= x then 
                do {
                  -- Prelude.putStrLn ("Auto Reachability [" ++ (show x) ++ "] Trace: " ++ (ppTrace tr)) 
                  -- return ()
                  Prelude.putStr ("-")
                } 
              else 
                do {
                  -- these are events reached now
                  let reached = Data.List.intersect events re;
                      monitored = Data.List.intersect events me;
                    in if reached /= [] then do {
                      Prelude.putStrLn ("*** These events " ++  show reached ++ " are reached! ***" ++ "\nTrace: " ++ (ppTrace tr));
                      Prelude.putStrLn ("");
                    }
                    else do {
                      if monitored /= [] then 
                        Prelude.putStrLn ("*** These events " ++  show monitored ++ " are monitored! ***");
                      else 
                        Prelude.putStr ("");
                      forM_ m $ \s -> simulate_cnt n (snd s) mod (steps+1) re me (tr ++ [fst s]) ;
                      when (steps == 0) (  Prelude.putStrLn ("*** Auto Reachability [" ++ (show x) ++ "] Finished ***") )
                    }
                }
            (RReach x) -> if steps >= x then 
            -- switch to manual after specified steps
                do {
                  -- Prelude.putStrLn ("Random Reachability [" ++ (show x) ++ "] Trace: " ++ (ppTrace tr)) 
                  -- return ()
                  Prelude.putStr ("-")
                } 
              else 
                do {
                  -- these are events reached now
                  let reached = Data.List.intersect events re;
                      monitored = Data.List.intersect events me;
                    in if reached /= [] then do {
                      Prelude.putStrLn ("*** These events " ++  show reached ++ " are reached! ***" ++ "\nTrace: " ++ (ppTrace tr));
                      Prelude.putStrLn ("");
                    }
                    else do {
                       if monitored /= [] then 
                        Prelude.putStrLn ("*** These events " ++  show monitored ++ " are monitored! ***");
                      else 
                        Prelude.putStr ("");

                      -- if there is only one event, we don't need to choose
                      if (Prelude.length m == 1) 
                      then do { 
                        -- Prelude.putStrLn ("Reachability Random: only 1" ++ "> " ++  (Prelude.show (fst (m !! (0))))) ; 
                        simulate_cnt 0 (snd (m !! (0))) mod (steps + 1) re me (tr ++ [fst (m !! (0))]) 
                        }
                      else
                        do {
                          rn <- applyAtomicGen (uniformR (1 :: Int, Prelude.length m)) globalStdGen;
                          -- let (rn, newg) = uniformR (1 :: Int, Prelude.length m)
                          -- in 
                          do { 
                            -- Prelude.putStrLn ("Random chosen: " ++ show rn ++ "> " ++ (Prelude.show (fst (m !! (rn-1))))) ; 
                            simulate_cnt 0 (snd (m !! (rn-1))) mod (steps + 1) re me (tr ++ [fst (m !! (rn-1))])
                          }
                        }
                      ;
                      when (steps == 0) (  Prelude.putStrLn ("*** Random Reachability [" ++ (show x) ++ "] Finished ***") )
                    }
                }
            (Feasible) -> case Data.List.uncons re of
              Nothing -> do {Prelude.putStrLn ("*** The specified trace is feasible ****")}
              Just (hd, tl) -> -- in if cur_event_to_check `elem` events then
                  case Data.List.elemIndex hd events of
                    Just rn -> do { 
                      simulate_cnt 0 (snd (m !! (rn))) mod (steps + 1) tl me (tr ++ [fst (m !! (rn))])
                    }
                    Nothing -> do {Prelude.putStrLn ("*** Event [" ++ hd ++ "] is not feasible in current state \nwhere feasible events include \t" ++ show events)}
                
            (Quit) -> Prelude.putStrLn "Simulation terminated";
            (Manual) -> do { 
              -- Manual
                 Prelude.putStrLn ("Events:\n" ++ Prelude.concat (map (\(n, e) -> " (" ++ ppShow n ++ ") " ++ removeSubstr "_C" e ++ ";\n") (zip [1..] events)));
                 -- Prelude.putStrLn ("Events:\n" ++ Prelude.concat (map (\(n, e) -> " (" ++ ppShow n ++ ") " ++ removeSubstr "_C" e ++ ";\n") (zip [1..] (map (\m -> (Prelude.show (fst m))) m))));
                 Prelude.putStr ("[Choose: 1-" ++ Prelude.show (Prelude.length m) ++ "]: ");
                 e <- Prelude.getLine;
                 
                 do {
                  -- try to parse AutoCmd 
                  case (Prelude.reads e)::[(AutoCmd, String)] of
                    []       -> do { 
                      -- Prelude.putStrLn "Not AutoCmd, use Manual";
                      -- Other commands
                      if (e == "q" || e == "Q") then
                        do {
                            Prelude.putStrLn ("*** Simulation terminated ***"); 
                            Prelude.putStrLn ("Trace: " ++ (ppTrace tr));
                            System.Exit.exitWith System.Exit.ExitSuccess
                        }
                      else if (e == "h" || e == "H") then
                        do {
                            Prelude.putStrLn ("*** Usage ***"); 
                            Prelude.putStrLn ("Auto n : Exhaustive search of traces up to n events or length;");
                            Prelude.putStrLn ("Rand n : Random search of a trace up to n events or length;");
                            Prelude.putStrLn ("AReach n %er1;er2;...%[#%em1;em2;...%] : Exhaustive search of traces up to n events or length, or if the specified events (er) are reached with optional events for monitor (em);");
                            Prelude.putStrLn ("RReach n %er1;er2;...%[#%em1;em2;...%] : Random search of a trace up to n events or length, or if the specified events (er) are reached with optional events for monitor (em);");
                            Prelude.putStrLn ("Feasible %event1;event2;...% : Check whether the specified sequence of events is a feasible trace from current state.\n");
                            -- System.Exit.exitWith System.Exit.ExitSuccess
                            simulate_cnt n t mod steps re me tr 
                        }
                      else
                        case (Prelude.reads e) of
                          []       -> if (Prelude.length m == 1)
                                        then do { Prelude.putStrLn ( (Prelude.show (fst (m !! 0)))) ; simulate_cnt 0 (snd (m !! (0))) mod steps re me (tr ++ [fst (m !! 0)]) }
                                        else do { Prelude.putStrLn "No parse"; simulate_cnt n t mod steps re me tr }
                          [(v, _)] -> if (v > Prelude.length m)
                                        then do { Prelude.putStrLn "Rejected"; simulate_cnt n t mod steps re me tr }
                                        else do { Prelude.putStrLn ( (Prelude.show (fst (m !! (v-1))))) ; simulate_cnt 0 (snd (m !! (v - 1))) mod steps re me (tr ++ [fst (m !! (v-1))]) }

                      }
                    -- parsed AutoCmd where r is the rest string after a, parsed AutoCmd 
                    [(a, r)] -> do {
                      Prelude.putStrLn (show a ++ ", " ++ r);
                      case a of 
                        (Auto x) ->  do { -- Prelude.putStrLn ("Auto " ++ show x); 
                            simulate_cnt n t a 0 [] [] tr }
                        (Rand x) ->  do { -- Prelude.putStrLn ("Random " ++ show x); 
                            simulate_cnt n t a 0 [] [] tr }
                        (AReach x) ->  do {
                          let (res,mes) = format_reach r
                          in do {
                            Prelude.putStrLn ("Reachability by Auto: " ++ show x ++ "\n  Events for reachability check: " ++ show res ++ "\n  Events for monitor: " ++ show mes); 
                            simulate_cnt n t a 0 res mes tr 
                          }
                        }
                        (RReach x) ->  do {
                          let (res,mes) = format_reach r
                          in do {
                            Prelude.putStrLn ("Reachability by Random: " ++ show x ++ "\n  Events for reachability check: " ++ show res ++ "\n  Events for monitor: " ++ show mes); 
                            simulate_cnt n t a 0 res mes tr 
                          }
                        }
                        (Feasible) ->  do {
                          let fe = format_events r
                          in do {
                            Prelude.putStrLn ("Feasibility check the sequence of events: " ++ show fe); simulate_cnt n t a 0 fe me tr 
                          }
                        }
                        (Quit) -> do {
                            Prelude.putStrLn ("*** Simulation terminated ***"); 
                            Prelude.putStrLn ("Trace: " ++ (ppTrace tr));
                            System.Exit.exitWith System.Exit.ExitSuccess
                        }
                        _ -> do {Prelude.putStrLn ("Unknown " ++ show a)}
                      }
                  }
              }
         }
         
--       if (e == "q" || e == "Q") then
--         Prelude.putStrLn "Simulation terminated"
--       else
--        case (Prelude.reads e) of
--          []       -> if (Prelude.length m == 1)
--                        then do { Prelude.putStrLn ( (Prelude.show (fst (m !! 0)))) ; simulate_cnt 0 (snd (m !! (0)))}
--                        else do { Prelude.putStrLn "No parse"; simulate_cnt n t }
--          [(v, _)] -> if (v > Prelude.length m)
--                        then do { Prelude.putStrLn "Rejected"; simulate_cnt n t }
--                        else do { Prelude.putStrLn ( (Prelude.show (fst (m !! (v-1))))) ; simulate_cnt 0 (snd (m !! (v - 1)))}
     };
simulate_cnt n t@(Vis (Pfun_of_map f)) mod steps re me tr = 
  do { Prelude.putStr ("Enter an event:");
       e <- Prelude.getLine;
       if (e == "q" || e == "Q") then
         Prelude.putStrLn "Simulation terminated"
       else
       case (Prelude.reads e) of
         []       -> do { Prelude.putStrLn "No parse"; simulate_cnt n t mod steps re me tr } 
         [(v, _)] -> case f v of
                       Nothing -> do { Prelude.putStrLn "Rejected"; simulate_cnt n t mod steps re me tr }
                       Just t' -> simulate_cnt 0 t' mod steps re me tr 
     };                                                                

simulate :: (Eq e, Prelude.Show e, Prelude.Read e, Prelude.Show s) => Itree e s -> Prelude.IO ();
simulate p = do { hSetBuffering stdout NoBuffering; putStrLn ""; putStrLn "Starting ITree Animation..."; simulate_cnt 0 p (Manual) 0 [] [] []}
