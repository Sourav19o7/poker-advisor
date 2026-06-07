import {simulate, decide, mulberry32} from './engine.mjs';

// ---- config ----
const N         = +(process.argv[2] || 1000);     // dataset size per player count
const REF_ITERS = +(process.argv[3] || 200000);   // "ground truth" iterations
const MODE      = process.argv.includes('--improved') ? 'improved' : 'baseline';
const PLAYERS   = [3,4,5,6];

// App's iteration setting per player count.
const appItersBaseline = p => (p<=4 ? 60000 : 40000);
const appItersImproved = p => 100000; // candidate: flat, higher
const appIters = MODE==='improved' ? appItersImproved : appItersBaseline;

// ---- scenario generation (seeded so dataset is identical across runs) ----
function genScenario(rng){
  const deck=[]; for(let id=8;id<60;id++) deck.push(id);
  // shuffle
  for(let i=deck.length-1;i>0;i--){ const j=Math.floor(rng()*(i+1)); [deck[i],deck[j]]=[deck[j],deck[i]]; }
  const r=rng();
  const boardLen = r<0.25?0 : r<0.60?3 : r<0.80?4 : 5;  // preflop/flop/turn/river mix
  const hero=[deck[0],deck[1]];
  const board=deck.slice(2,2+boardLen);
  return {hero,board};
}

function stats(arr){
  const s=[...arr].sort((a,b)=>a-b);
  const mean=arr.reduce((a,b)=>a+b,0)/arr.length;
  const rmse=Math.sqrt(arr.reduce((a,b)=>a+b*b,0)/arr.length);
  return {mean, max:s[s.length-1], p95:s[Math.floor(s.length*0.95)], rmse};
}

console.log(`\n=== Poker engine accuracy — ${MODE} ===`);
console.log(`dataset=${N}/playercount  reference=${REF_ITERS} iters\n`);
console.log('players | appIter |  equity MAE  |   p95   |   max   | dec-agree(bet) | dec-agree(check) | flip-rate');
console.log('--------|---------|--------------|---------|---------|----------------|------------------|----------');

const summary=[];
for(const p of PLAYERS){
  const ai = appIters(p);
  const scenRng = mulberry32(12345 + p); // same dataset per player count across modes
  const errs=[];
  let agreeBet=0, agreeCheck=0, flips=0;

  for(let i=0;i<N;i++){
    const {hero,board}=genScenario(scenRng);

    // ground truth equity
    const ref = simulate(hero,board,p,REF_ITERS).equity;

    // app estimate (two independent runs -> measure flip)
    const a1 = simulate(hero,board,p,ai, mulberry32(1000+i));
    const a2 = simulate(hero,board,p,ai, mulberry32(9000+i));

    errs.push(Math.abs(a1.equity - ref)*100); // percentage points

    // decision agreement vs reference, facing a 2/3-pot bet (pot=100, call=66)
    const refDecBet = decide(ref, p, 100, 66);
    const appDecBet = decide(a1.equity, p, 100, 66);
    if(refDecBet===appDecBet) agreeBet++;

    // decision agreement, no bet to call (bet vs check)
    const refDecChk = decide(ref, p, 100, 0);
    const appDecChk = decide(a1.equity, p, 100, 0);
    if(refDecChk===appDecChk) agreeCheck++;

    // flip rate: does the verdict change between two app runs? (check both contexts)
    if(decide(a1.equity,p,100,66)!==decide(a2.equity,p,100,66)) flips++;
    else if(decide(a1.equity,p,100,0)!==decide(a2.equity,p,100,0)) flips++;
  }

  const st=stats(errs);
  const row={
    p, ai,
    mae:st.mean, p95:st.p95, max:st.max,
    agreeBet:agreeBet/N*100, agreeCheck:agreeCheck/N*100, flip:flips/N*100
  };
  summary.push(row);
  console.log(
    `   ${p}    | ${String(ai).padStart(6)}  |  ${st.mean.toFixed(3)} pp  | ${st.p95.toFixed(2)}pp | ${st.max.toFixed(2)}pp |    ${row.agreeBet.toFixed(1)}%      |     ${row.agreeCheck.toFixed(1)}%       |  ${row.flip.toFixed(2)}%`
  );
}
console.log('\n(MAE/p95/max = abs error of app equity vs reference, in percentage points)');
console.log('(dec-agree = % of hands where app verdict matches reference verdict)');
console.log('(flip-rate = % of hands where two app runs give different verdicts)\n');
