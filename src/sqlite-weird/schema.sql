-- DEMO ONLY. Install once; the entire procedure survives closing the connection.
BEGIN IMMEDIATE;
CREATE TABLE gates (
  wire INTEGER PRIMARY KEY CHECK(wire BETWEEN 14 AND 78),
  name TEXT NOT NULL UNIQUE,
  a INTEGER NOT NULL CHECK(a >= 0 AND a < wire),
  b INTEGER NOT NULL CHECK(b >= 0 AND b < wire)
);
-- Each full adder uses nine NANDs. Wire number is also evaluation order.
WITH bits(i) AS (VALUES(0),(1),(2),(3),(4),(5)),
steps(j,label) AS (VALUES(0,'ab'),(1,'ax'),(2,'bx'),(3,'xor'),
 (4,'xc'),(5,'xp'),(6,'cp'),(7,'sum'),(8,'carry'))
INSERT INTO gates
SELECT 14+9*i+j, label || i,
 CASE j WHEN 0 THEN 2+i WHEN 1 THEN 2+i WHEN 2 THEN 8+i
 WHEN 3 THEN 15+9*i WHEN 4 THEN 17+9*i WHEN 5 THEN 17+9*i
 WHEN 6 THEN CASE WHEN i=0 THEN 0 ELSE 13+9*i END
 WHEN 7 THEN 19+9*i WHEN 8 THEN 14+9*i END,
 CASE j WHEN 0 THEN 8+i WHEN 1 THEN 14+9*i WHEN 2 THEN 14+9*i
 WHEN 3 THEN 16+9*i WHEN 4 THEN CASE WHEN i=0 THEN 0 ELSE 13+9*i END
 WHEN 5 THEN 18+9*i WHEN 6 THEN 18+9*i WHEN 7 THEN 20+9*i
 WHEN 8 THEN 18+9*i END
FROM bits CROSS JOIN steps;
-- S5 AND (S4 OR (S3 AND (S2 OR S1 OR S0))) is greater-than-40.
INSERT INTO gates VALUES
 (68,'not_s0',21,21),(69,'not_s1',30,30),(70,'low01',68,69),
 (71,'not_low01',70,70),(72,'not_s2',39,39),(73,'low012',71,72),
 (74,'not_mid',48,73),(75,'not_s4',57,57),(76,'upper',75,74),
 (77,'not_stop',66,76),(78,'stop',77,77);
CREATE VIEW wires AS
SELECT 0 AS wire,'zero' AS name UNION ALL SELECT 1,'one'
UNION ALL SELECT 2,'acc0' UNION ALL SELECT 3,'acc1'
UNION ALL SELECT 4,'acc2' UNION ALL SELECT 5,'acc3'
UNION ALL SELECT 6,'acc4' UNION ALL SELECT 7,'acc5'
UNION ALL SELECT 8,'hours0' UNION ALL SELECT 9,'hours1'
UNION ALL SELECT 10,'hours2' UNION ALL SELECT 11,'hours3'
UNION ALL SELECT 12,'hours4' UNION ALL SELECT 13,'hours5'
UNION ALL SELECT wire,name FROM gates;
CREATE TABLE runs (
 id INTEGER PRIMARY KEY,
 seed INTEGER NOT NULL CHECK(typeof(seed)='integer' AND seed BETWEEN 1 AND 2147483646),
 run_date TEXT NOT NULL CHECK(date(run_date,'+0 days') IS run_date),
 status TEXT NOT NULL CHECK(status IN ('running','complete')),
 demo_only INTEGER NOT NULL DEFAULT 1 CHECK(demo_only=1)
);
CREATE UNIQUE INDEX one_active_run ON runs(status) WHERE status='running';
CREATE TABLE trace (
 run_id INTEGER NOT NULL REFERENCES runs(id), card INTEGER NOT NULL,
 gate INTEGER NOT NULL, rng INTEGER NOT NULL, hours INTEGER NOT NULL,
 signals TEXT NOT NULL CHECK(json_valid(signals)),
 PRIMARY KEY(run_id,card,gate)
);
-- One clock, two transitions: evaluate a gate, or load the next card's inputs.
-- No decimal accumulator exists here. The ONLY gate evaluator is NAND.
CREATE VIEW clock AS
WITH RECURSIVE ticks(run_id,card,gate,rng,hours,signals) AS (
 SELECT id,1,13,seed*16807%2147483647,10+(seed*16807%2147483647)%10,
 json_array(0,1,0,0,0,0,0,0,
 ((10+(seed*16807%2147483647)%10)>>0)&1,
 ((10+(seed*16807%2147483647)%10)>>1)&1,
 ((10+(seed*16807%2147483647)%10)>>2)&1,
 ((10+(seed*16807%2147483647)%10)>>3)&1,
 ((10+(seed*16807%2147483647)%10)>>4)&1,0)
 FROM runs WHERE status='running'
 UNION ALL
 SELECT run_id,card,g.wire,rng,hours,
 json_insert(signals,'$[#]',NOT (json_extract(signals,'$['||g.a||']')
 AND json_extract(signals,'$['||g.b||']')))
 FROM ticks JOIN gates g ON g.wire=ticks.gate+1
 UNION ALL
 SELECT run_id,card+1,13,rng*16807%2147483647,10+(rng*16807%2147483647)%10,
 json_array(0,1,
 json_extract(signals,'$[21]'),json_extract(signals,'$[30]'),
 json_extract(signals,'$[39]'),json_extract(signals,'$[48]'),
 json_extract(signals,'$[57]'),json_extract(signals,'$[66]'),
 ((10+(rng*16807%2147483647)%10)>>0)&1,
 ((10+(rng*16807%2147483647)%10)>>1)&1,
 ((10+(rng*16807%2147483647)%10)>>2)&1,
 ((10+(rng*16807%2147483647)%10)>>3)&1,
 ((10+(rng*16807%2147483647)%10)>>4)&1,0)
 FROM ticks WHERE gate=78 AND json_extract(signals,'$[78]')=0 AND card<5
)
SELECT * FROM ticks;
-- Decimal conversion is reporting only; these values never feed the clock.
CREATE VIEW completed_cards AS
SELECT run_id,card,hours,rng,signals,
 json_extract(signals,'$[21]') + 2*json_extract(signals,'$[30]')
 +4*json_extract(signals,'$[39]') +8*json_extract(signals,'$[48]')
 +16*json_extract(signals,'$[57]') +32*json_extract(signals,'$[66]') AS total,
 json_extract(signals,'$[78]') AS stop
FROM trace WHERE gate=78;
CREATE TABLE ledger (
 run_id INTEGER NOT NULL REFERENCES runs(id), card INTEGER NOT NULL,
 category TEXT NOT NULL, hours INTEGER NOT NULL, total INTEGER NOT NULL,
 iso_week TEXT NOT NULL, demo_only INTEGER NOT NULL CHECK(demo_only=1),
 PRIMARY KEY(run_id,card)
);
CREATE VIEW run_weeks AS
WITH thursdays AS (
 SELECT id,date(run_date,printf('%+d days',3-(cast(strftime('%w',run_date) AS INTEGER)+6)%7)) AS thu
 FROM runs
)
SELECT id,strftime('%Y',thu)||'-W'||printf('%02d',1+(cast(strftime('%j',thu) AS INTEGER)-1)/7) AS iso_week
FROM thursdays;
CREATE VIEW run_demo AS SELECT NULL AS seed,NULL AS run_date WHERE 0;
CREATE TRIGGER execute_demo INSTEAD OF INSERT ON run_demo BEGIN
 INSERT INTO runs(seed,run_date,status)
 VALUES(coalesce(NEW.seed,1+((random() & 2147483647)%2147483646)),
 coalesce(NEW.run_date,date('now')),'running');
 INSERT INTO trace SELECT * FROM clock;
 SELECT CASE WHEN NOT EXISTS (
 SELECT 1 FROM completed_cards c JOIN runs r ON r.id=c.run_id
 WHERE r.status='running' AND c.stop=1
 ) THEN RAISE(ABORT,'DEMO ONLY: circuit did not halt') END;
 INSERT INTO ledger
 SELECT c.run_id,c.card,
 CASE (c.card-1)%4 WHEN 0 THEN 'Meetings' WHEN 1 THEN 'Coding'
 WHEN 2 THEN 'Debugging' ELSE 'Learning' END,c.hours,c.total,w.iso_week,1
 FROM completed_cards c JOIN runs r ON r.id=c.run_id
 JOIN run_weeks w ON w.id=r.id WHERE r.status='running';
 UPDATE runs SET status='complete' WHERE status='running';
END;
PRAGMA user_version=1;
COMMIT;
