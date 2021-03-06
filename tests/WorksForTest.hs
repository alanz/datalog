{-# LANGUAGE OverloadedStrings, FlexibleContexts #-}
module Main ( main ) where

import Data.Hashable
import Data.Set ( fromList )
import Data.Text ( Text )
import Test.Framework ( defaultMain, testGroup, Test )
import Test.Framework.Providers.HUnit
import Test.HUnit hiding ( Test )

import Database.Datalog

main :: IO ()
main = defaultMain tests

tests :: [Test]
tests = [ testGroup "t1" [ testCase "1" t1
                         , testCase "2" t2
                         , testCase "3" t3
                         , testCase "4" t4
                         ]
        ]

data WorkInfo = EID !Int -- id
              | EN !Text -- Name
              | EP !Text -- Position
              | J !Text  -- Job
              | EA !Int
              deriving (Eq, Ord, Show)

instance Hashable WorkInfo where
  hashWithSalt s (EID i) = s `hashWithSalt` i `hashWithSalt` (1 :: Int)
  hashWithSalt s (EN n) = s `hashWithSalt` n `hashWithSalt` (2 :: Int)
  hashWithSalt s (EP p) = s `hashWithSalt` p `hashWithSalt` (3 :: Int)
  hashWithSalt s (J j) = s `hashWithSalt` j `hashWithSalt` (4 :: Int)
  hashWithSalt s (EA a) = s `hashWithSalt` a `hashWithSalt` (5 :: Int)

db1 :: Maybe (Database WorkInfo)
db1 = makeDatabase $ do
  employee <- addRelation "employee" 4
  let emplFacts = [ [ EID 1, EN "Bob", EP "Boss", EA 51]
                  , [ EID 2, EN "Mary", EP "Chief Accountant", EA 31]
                  , [ EID 3, EN "John", EP "Accountant", EA 22 ]
                  , [ EID 4, EN "Sameer", EP "Chief Programmer", EA 34 ]
                  , [ EID 5, EN "Lilian", EP "Programmer", EA 24 ]
                  , [ EID 6, EN "Li", EP "Technician", EA 40 ]
                  , [ EID 7, EN "Fred", EP "Sales", EA 29 ]
                  , [ EID 8, EN "Brenda", EP "Sales", EA 27 ]
                  , [ EID 9, EN "Miki", EP "Project Management", EA 44 ]
                  , [ EID 10, EN "Albert", EP "Technician", EA 23 ]
                  ]
  mapM_ (assertFact employee) emplFacts

  bossOf <- addRelation "bossOf" 2
  let bossFacts = [ [ EID 1, EID 2 ]
                  , [ EID 2, EID 3 ]
                  , [ EID 1, EID 4 ]
                  , [ EID 4, EID 5 ]
                  , [ EID 4, EID 6 ]
                  , [ EID 1, EID 7 ]
                  , [ EID 7, EID 8 ]
                  , [ EID 1, EID 9 ]
                  , [ EID 6, EID 10 ]
                  ]
  mapM_ (assertFact bossOf) bossFacts

  canDo <- addRelation "canDo" 2
  let canDoFacts = [ [ EP "Boss", J "Management" ]
                   , [ EP "Accountant", J "Accounting"  ]
                   , [ EP "Chief Accountant", J "Accounting" ]
                   , [ EP "Programmer", J "Programming" ]
                   , [ EP "Chief Programmer", J "Programming" ]
                   , [ EP "Technician", J "Server Support" ]
                   , [ EP "Sales", J "Sales" ]
                   , [ EP "Project Management", J "Project Management" ]
                   ]
  mapM_ (assertFact canDo) canDoFacts

  jobCanBeDoneBy <- addRelation "jobCanBeDoneBy" 2
  let replaceFacts = [ [ J "PC Support", J "Server Support" ]
                     , [ J "PC Support", J "Programming" ]
                     , [ J "Payroll", J "Accounting" ]
                     ]
  mapM_ (assertFact jobCanBeDoneBy) replaceFacts

  jobExceptions <- addRelation "jobExceptions" 2
  assertFact jobExceptions [ EID 4, J "PC Support" ]

q1 :: (Failure DatalogError m) => QueryBuilder m WorkInfo (Query WorkInfo)
q1 = do
  employee <- relationPredicateFromName "employee"
  bossOf <- relationPredicateFromName "bossOf"
  worksFor <- inferencePredicate "worksFor"
  let x = LogicVar "X"
      y = LogicVar "Y"
      z = LogicVar "Z"
      eid = LogicVar "E-ID"
      bid = LogicVar "B-ID"
  (worksFor, [x, y]) |- [ lit bossOf [bid, eid]
                        , lit employee [eid, x, Anything, Anything]
                        , lit employee [bid, y, Anything, Anything]
                        ]
  (worksFor, [x, y]) |- [ lit worksFor [x, z]
                        , lit worksFor [z, y]
                        ]
  issueQuery worksFor [ BindVar "name", x ]

t1 :: Assertion
t1 = do
  let Just db = db1
      Just qp = buildQueryPlan db q1

  res <- executeQueryPlan qp db [("name", EN "Albert")]
  assertEqual "t1" expected (fromList res)
  where
    expected = fromList [ [EN "Albert", EN "Li"]
                        , [EN "Albert", EN "Sameer"]
                        , [EN "Albert", EN "Bob"]
                        ]
t2 :: Assertion
t2 = do
  let Just db = db1
      Just qp = buildQueryPlan db q1

  res <- executeQueryPlan qp db [("name", EN "Lilian")]
  assertEqual "t2" expected (fromList res)
  where
    expected = fromList [ [EN "Lilian", EN "Sameer"]
                        , [EN "Lilian", EN "Bob"]
                        ]

q2 :: (Failure DatalogError m) => QueryBuilder m WorkInfo (Query WorkInfo)
q2 = do
  employee <- relationPredicateFromName "employee"
  bossOf <- relationPredicateFromName "bossOf"
  worksFor <- inferencePredicate "worksFor"
  worksForYoung <- inferencePredicate "worksForYoung"
  let x = LogicVar "X"
      y = LogicVar "Y"
      z = LogicVar "Z"
      age = LogicVar "Age"
      eid = LogicVar "E-ID"
      bid = LogicVar "B-ID"
  (worksFor, [x, y]) |- [ lit bossOf [bid, eid]
                        , lit employee [eid, x, Anything, Anything]
                        , lit employee [bid, y, Anything, Anything]
                        ]
  (worksFor, [x, y]) |- [ lit worksFor [x, z]
                        , lit worksFor [z, y]
                        ]
  (worksForYoung, [x, y]) |- [ lit worksFor [x, y]
                             , lit employee [eid, y, Anything, age]
                             , cond1 (\(EA a) -> a < 49) age
                             ]
  issueQuery worksForYoung [ BindVar "name", y ]

t3 :: Assertion
t3 = do
  let Just db = db1
      Just qp = buildQueryPlan db q2

  res <- executeQueryPlan qp db [("name", EN "Lilian")]
  assertEqual "t3" expected (fromList res)
  where
    expected = fromList [ [EN "Lilian", EN "Sameer"]
                        ]


q3 :: (Failure DatalogError m) => QueryBuilder m WorkInfo (Query WorkInfo)
q3 = do
  employee <- relationPredicateFromName "employee"
  bossOf <- relationPredicateFromName "bossOf"
  worksFor <- inferencePredicate "worksFor"
  empJobStar <- inferencePredicate "employeeJob*"
  empJob <- inferencePredicate "employeeJob"
  canDo <- relationPredicateFromName "canDo"
  jobReplacement <- relationPredicateFromName "jobCanBeDoneBy"
  jobExceptions <- relationPredicateFromName "jobExceptions"
  bj <- inferencePredicate "bj"
  let x = LogicVar "X"
      y = LogicVar "Y"
      z = LogicVar "Z"
      jid = LogicVar "ID"
      pos = LogicVar "Pos"
      eid = LogicVar "E-ID"
      bid = LogicVar "B-ID"
  (worksFor, [x, y]) |- [ lit bossOf [bid, eid]
                        , lit employee [eid, x, Anything, Anything]
                        , lit employee [bid, y, Anything, Anything]
                        ]
  (worksFor, [x, y]) |- [ lit worksFor [x, z]
                        , lit worksFor [z, y]
                        ]
  (empJobStar, [x, y]) |- [ lit employee [Anything, x, pos, Anything]
                          , lit canDo [pos, y]
                          ]
  (empJobStar, [x, y]) |- [ lit jobReplacement [y, z]
                          , lit empJobStar [x, z]
                          ]
  (empJobStar, [x, y]) |- [ lit canDo [Anything, y]
                          , lit employee [Anything, x, Atom (EP "Boss"), Anything]
                          ]
  (empJob, [x, y]) |- [ lit empJobStar [x, y]
                      , lit employee [jid, x, Anything, Anything]
                      , negLit jobExceptions [jid, y]
                      ]
  --(bj, [x, y]) |- [ lit worksFor [x, y]
  --                , negLit empJob [y, Atom (J "PC Support")]
  --                ]
  issueQuery empJob [ BindVar "name", x ]

t4 :: Assertion
t4 = do
  let Just db = db1
      Just qp = buildQueryPlan db q3

  res <- executeQueryPlan qp db [("name", EN "Li")]
  assertEqual "t4" expected (fromList res)
  where
    expected = fromList [ [EN "Li", J "PC Support"]
                        , [EN "Li", J "Server Support"]
                        ]
