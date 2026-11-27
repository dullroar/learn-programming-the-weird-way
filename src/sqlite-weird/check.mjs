// Independent arithmetic is allowed ONLY in this test oracle.
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const source = readFileSync(new URL('schema.sql', import.meta.url), 'utf8');
const report = readFileSync(new URL('report.sql', import.meta.url), 'utf8');
const make = () => { const db = new DatabaseSync(':memory:'); db.exec(source); return db; };
const db = make();
const rows = (sql, ...args) => db.prepare(sql).all(...args);
const bits = n => Array.from({length:6}, (_, i) => (n >> i) & 1);
const decode = (s, offsets) => offsets.reduce((n, k, i) => n + s[k] * 2**i, 0);
const sums = [21,30,39,48,57,66];
const gates = rows('SELECT * FROM gates ORDER BY wire');
assert.equal(gates.length, 65);
gates.forEach((g, i) => {
  assert.equal(g.wire, 14+i);
  for (const k of [g.a,g.b]) assert(k >= 0 && k < g.wire);
});

// Exercise the EXACT stored SQL gate evaluator, with a supplied test anchor.
// Removing the card transition isolates one combinational evaluation.
const clock = db.prepare("SELECT sql FROM sqlite_schema WHERE name='clock'").get().sql;
const evaluator = clock.slice(clock.indexOf(' SELECT run_id,card,g.wire'), clock.indexOf('\n UNION ALL\n SELECT run_id,card+1'));
const statement = d => d.prepare(`WITH RECURSIVE ticks(run_id,card,gate,rng,hours,signals) AS (
 SELECT 0,1,?,1,0,? UNION ALL ${evaluator}
) SELECT gate,signals FROM ticks ORDER BY gate`);
function evaluate(d, signals, start=13) {
  const trace = statement(d).all(start, JSON.stringify(signals));
  assert.equal(trace.length, 79-start);
  trace.forEach(t => {
    const s = JSON.parse(t.signals);
    assert.equal(s.length, t.gate+1);
    assert(s.every(v => v===0 || v===1));
    if (t.gate > start) {
      const g = d.prepare('SELECT * FROM gates WHERE wire=?').get(t.gate);
      assert.equal(s[t.gate], Number(!(s[g.a] && s[g.b])));
    }
  });
  return JSON.parse(trace.at(-1).signals);
}
function exhaustive(d) {
  for (let a=0; a<=40; a++) for (let b=10; b<=19; b++) {
    const s = evaluate(d, [0,1,...bits(a),...bits(b)]);
    assert.equal(decode(s,sums), a+b, `adder ${a}+${b}`);
    assert.equal(s[78], Number(a+b>40), `stop ${a}+${b}`);
  }
}
exhaustive(db);
for (let n=0; n<64; n++) {
  const s = Array(68).fill(0); s[1]=1;
  sums.forEach((k,i) => s[k]=bits(n)[i]);
  assert.equal(evaluate(db,s,67)[78], Number(n>40), `comparator ${n}`);
}

// Enforce the computation boundary as a reviewed, narrow SQL surface.
const clean = source.replace(/--[^\n]*/g,'');
assert.equal((clean.match(/WITH RECURSIVE/gi)||[]).length,1);
assert.match(evaluator,/json_insert\(signals,'\$\[#\]',NOT \(json_extract/);
assert(!/\b(total|sum|hours)\s*(\+|>|>=)|\b(sum|total)\s*\(/i.test(clock));
assert(!/\b(40|41)\b/.test(clock));
assert.match(clock,/gate=78 AND json_extract\(signals,'\$\[78\]'\)=0 AND card<5/);
assert.match(clock,/json_array\(0,1,\s*json_extract\(signals,'\$\[21\]'\)/);
for (const file of ['run.sh','report.sql']) {
  const s = readFileSync(new URL(file,import.meta.url),'utf8');
  assert(!/\b(update|insert into)\s+(ledger|trace|gates|runs)\b/i.test(s));
}

const categories=['Meetings','Coding','Debugging','Learning'];
function validate(d, id) {
  const run=d.prepare('SELECT * FROM runs WHERE id=?').get(id);
  assert.equal(run.status,'complete'); assert.equal(run.demo_only,1);
  const cards=d.prepare('SELECT * FROM ledger WHERE run_id=? ORDER BY card').all(id);
  assert(cards.length>=3 && cards.length<=5);
  let total=0, rng=run.seed;
  cards.forEach((c,i) => {
    assert(total<=40); rng=rng*16807%2147483647;
    assert.equal(c.hours,10+rng%10); assert.equal(c.card,i+1);
    assert.equal(c.category,categories[i%4]); assert.equal(c.demo_only,1);
    total+=c.hours; assert.equal(c.total,total);
    const trace=d.prepare('SELECT * FROM trace WHERE run_id=? AND card=? ORDER BY gate').all(id,c.card);
    assert.equal(trace.length,66);
    trace.forEach((t,j) => {
      assert.equal(t.gate,13+j); assert.equal(t.rng,rng); assert.equal(t.hours,c.hours);
      const s=JSON.parse(t.signals);
      assert(s.every(x=>x===0 || x===1)); assert.equal(s.length,t.gate+1);
      if(j) { const g=gates[j-1]; assert.equal(s[g.wire],Number(!(s[g.a]&&s[g.b]))); }
    });
    const s=JSON.parse(trace.at(-1).signals);
    assert.equal(decode(s,[2,3,4,5,6,7]),total-c.hours);
    assert.equal(decode(s,[8,9,10,11,12,13]),c.hours);
    assert.equal(decode(s,sums),c.total); assert.equal(s[78],Number(total>40));
    assert.equal(s[78],Number(i===cards.length-1));
  });
  assert(total>40 && total<=59);
  return cards;
}
function run(d, seed=12345, date='2021-01-01') {
  d.prepare('INSERT INTO run_demo(seed,run_date) VALUES(?,?)').run(seed,date);
  return d.prepare('SELECT max(id) id FROM runs').get().id;
}
const first=validate(db,run(db));
const second=validate(db,run(db));
assert.deepEqual(first.map(({run_id,...c})=>c),second.map(({run_id,...c})=>c));
const dates=[['2019-12-30','2020-W01'],['2020-12-31','2020-W53'],
 ['2021-01-01','2020-W53'],['2021-01-04','2021-W01'],['2022-01-01','2021-W52']];
for (const [date,week] of dates) validate(db,run(db,1,date)).forEach(c=>assert.equal(c.iso_week,week));
for (let i=0;i<30;i++) validate(db,run(db,null,null));
// Find a deterministic five-card run, which necessarily retains total=40.
let fiveSeed=1;
for (;;fiveSeed++) {
  let r=fiveSeed,t=0,n=0;
  while(t<=40) { r=r*16807%2147483647;t+=10+r%10;n++; }
  if(n===5) break;
}
assert.equal(validate(db,run(db,fiveSeed)).length,5);

// Every report result is generated from the saved rows, including bit strings.
const id=run(db);
const statements=report.replace(/--[^\n]*/g,'').split(';').map(s=>s.trim()).filter(Boolean);
const results=statements.map(s=>db.prepare(s).all());
assert(results[0][0].demo.includes('DEMO ONLY'));
assert.deepEqual(results[1].map(({marker,...c})=>c),validate(db,id).map(({run_id,card,demo_only,...c})=>c));
results[3].forEach((c,i)=>{
  const ledger=first[i]; // Reproducible default test seed/date.
  assert.equal(parseInt([...c.sum_bits].reverse().join(''),2),ledger.total);
  assert.equal(parseInt([...c.operand_a].reverse().join(''),2),ledger.total-ledger.hours);
  assert.equal(parseInt([...c.operand_b].reverse().join(''),2),ledger.hours);
  const signals=JSON.parse(db.prepare('SELECT signals FROM trace WHERE run_id=? AND card=? AND gate=78').get(id,i+1).signals);
  assert.equal(c.carry,[22,31,40,49,58,67].map(k=>signals[k]).join(''));
  assert.equal(c.stop,Number(i===first.length-1));
  assert.equal(c.marker,'DEMO ONLY');
});

// Counterfactuals prove the stored connections drive behavior.
const badAdder=make(); badAdder.exec('UPDATE gates SET a=0,b=0 WHERE wire=21');
assert.throws(()=>exhaustive(badAdder)); badAdder.close();
const forced=make(); forced.exec('UPDATE gates SET a=0,b=0 WHERE wire=78');
assert.throws(()=>validate(forced,run(forced))); forced.close();
// Force stop low: the five-card guard must abort the ENTIRE procedure.
const failed=make(); failed.exec('UPDATE gates SET a=1,b=1 WHERE wire=78');
assert.throws(()=>run(failed),/circuit did not halt/);
for (const t of ['runs','trace','ledger']) assert.equal(failed.prepare(`SELECT count(*) n FROM ${t}`).get().n,0);
failed.close();
// A mid-execution storage error rolls back this run but preserves previous ones.
const before=rows('SELECT count(*) n FROM trace')[0].n;
db.exec("CREATE TRIGGER fail_trace BEFORE INSERT ON trace WHEN NEW.gate=20 BEGIN SELECT RAISE(ABORT,'injected failure'); END;");
const runCount=rows('SELECT count(*) n FROM runs')[0].n;
assert.throws(()=>run(db),/injected failure/);
assert.equal(rows('SELECT count(*) n FROM runs')[0].n,runCount);
assert.equal(rows('SELECT count(*) n FROM trace')[0].n,before);
db.exec('DROP TRIGGER fail_trace');
for (const seed of [0,-1,2147483647,1.5,'oops']) assert.throws(()=>run(db,seed));
for (const date of ['2021-02-30','bad','2021-1-01']) assert.throws(()=>run(db,1,date));
assert.throws(()=>db.exec('INSERT INTO runs(seed,run_date,status,demo_only) VALUES(1,\'2021-01-01\',\'running\',0)'));
db.close();
const temp=mkdtempSync(join(tmpdir(),'sqlite-nand-'));
try {
  const path=join(temp,'demo.db'); let disk=new DatabaseSync(path); disk.exec(source); run(disk); disk.close();
  disk=new DatabaseSync(path); disk.exec('INSERT INTO run_demo DEFAULT VALUES;');
  validate(disk,2); assert.equal(disk.prepare('SELECT count(*) n FROM runs').get().n,2); disk.close();
} finally { rmSync(temp,{recursive:true,force:true}); }
console.log('OK: DEMO ONLY | 410 additions, 64 comparator inputs, saved NAND traces, deterministic/random runs, ISO weeks, reports, mutations, rollback and reopen');
