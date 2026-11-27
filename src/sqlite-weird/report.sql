-- DEMO ONLY: all displayed arithmetic is decoding already-computed wires.
SELECT 'DEMO ONLY | NAND computer | run '||id||' | seed '||seed AS demo
FROM runs WHERE id=(SELECT max(id) FROM runs);
SELECT category,hours,total,iso_week,'DEMO ONLY' AS marker FROM ledger
WHERE run_id=(SELECT max(id) FROM runs) ORDER BY card;
SELECT 'DEMO ONLY | bits below are least significant first, carry = outgoing carry at each bit' AS explanation;
SELECT c.card,
 json_extract(signals,'$[2]')||json_extract(signals,'$[3]')||json_extract(signals,'$[4]')||json_extract(signals,'$[5]')||json_extract(signals,'$[6]')||json_extract(signals,'$[7]') AS operand_a,
 json_extract(signals,'$[8]')||json_extract(signals,'$[9]')||json_extract(signals,'$[10]')||json_extract(signals,'$[11]')||json_extract(signals,'$[12]')||json_extract(signals,'$[13]') AS operand_b,
 json_extract(signals,'$[22]')||json_extract(signals,'$[31]')||json_extract(signals,'$[40]')||json_extract(signals,'$[49]')||json_extract(signals,'$[58]')||json_extract(signals,'$[67]') AS carry,
 json_extract(signals,'$[21]')||json_extract(signals,'$[30]')||json_extract(signals,'$[39]')||json_extract(signals,'$[48]')||json_extract(signals,'$[57]')||json_extract(signals,'$[66]') AS sum_bits,
 stop,'DEMO ONLY' AS marker
FROM completed_cards c WHERE run_id=(SELECT max(id) FROM runs) ORDER BY card;
