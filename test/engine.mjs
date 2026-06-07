// Shared poker engine (mirrors index.html) — optimized evaluator.
// Card id = rank*4 + suit, rank 2..14, suit 0..3  => ids 8..59.

const RANKS = [2,3,4,5,6,7,8,9,10,11,12,13,14];

// Preallocated scratch (single-threaded, reused per call).
const _rc = new Int8Array(15);
const _sc = new Int8Array(4);
const _sm = new Int32Array(4);

function straightHigh(mask){
  if(mask & (1<<14)) mask |= (1<<1); // ace low
  for(let hi=14; hi>=5; hi--){
    if((mask & (0b11111 << (hi-4))) === (0b11111 << (hi-4))) return hi;
  }
  return 0;
}

export function evaluate7(ids){
  _rc.fill(0); _sc.fill(0); _sm.fill(0);
  let rankMask = 0;
  for(let i=0;i<ids.length;i++){
    const id = ids[i], r = id>>2, s = id&3;
    _rc[r]++; _sc[s]++; _sm[s] |= (1<<r); rankMask |= (1<<r);
  }
  let flushSuit = -1;
  for(let s=0;s<4;s++) if(_sc[s]>=5){ flushSuit=s; break; }

  // straight flush
  if(flushSuit>=0){
    const sf = straightHigh(_sm[flushSuit]);
    if(sf>0) return 8*1048576 + sf;
  }
  // group ranks by multiplicity (high to low)
  let q=0,t=0,t2=0,p1=0,p2=0;
  for(let r=14;r>=2;r--){
    const n=_rc[r];
    if(n===4) q=r;
    else if(n===3){ if(!t) t=r; else if(!t2) t2=r; }
    else if(n===2){ if(!p1) p1=r; else if(!p2) p2=r; }
  }
  const enc=(c,a=0,b=0,cc=0,d=0,e=0)=>c*1048576 + a*65536 + b*4096 + cc*256 + d*16 + e;

  // four of a kind
  if(q){
    let k=0; for(let r=14;r>=2;r--){ if(r!==q && _rc[r]>0){ k=r; break; } }
    return enc(7,q,k);
  }
  // full house
  if(t && (t2 || p1)) return enc(6, t, t2||p1);
  // flush
  if(flushSuit>=0){
    const m=_sm[flushSuit]; const rs=[];
    for(let r=14;r>=2 && rs.length<5;r--) if(m & (1<<r)) rs.push(r);
    return enc(5,rs[0],rs[1],rs[2],rs[3],rs[4]);
  }
  // straight
  const st=straightHigh(rankMask);
  if(st>0) return enc(4,st);
  // trips
  if(t){
    let k1=0,k2=0;
    for(let r=14;r>=2;r--){ if(_rc[r]===1){ if(!k1)k1=r; else if(!k2){k2=r;break;} } }
    return enc(3,t,k1,k2);
  }
  // two pair
  if(p1 && p2){
    let k=0; for(let r=14;r>=2;r--){ if(r!==p1&&r!==p2&&_rc[r]>0){k=r;break;} }
    return enc(2,p1,p2,k);
  }
  // one pair
  if(p1){
    let k1=0,k2=0,k3=0;
    for(let r=14;r>=2;r--){ if(_rc[r]===1){ if(!k1)k1=r; else if(!k2)k2=r; else if(!k3){k3=r;break;} } }
    return enc(1,p1,k1,k2,k3);
  }
  // high card
  let a=0,b=0,c=0,d=0,e=0;
  for(let r=14;r>=2;r--){ if(_rc[r]===1){ if(!a)a=r;else if(!b)b=r;else if(!c)c=r;else if(!d)d=r;else if(!e){e=r;break;} } }
  return enc(0,a,b,c,d,e);
}

export const HAND_NAMES=['High card','One pair','Two pair','Three of a kind','Straight','Flush','Full house','Four of a kind','Straight flush'];

// Monte Carlo. rng is a function -> [0,1). Returns {win,tie,equity}.
export function simulate(heroIds, boardIds, players, iters, rng=Math.random){
  const known = new Uint8Array(60);
  for(const id of heroIds) known[id]=1;
  for(const id of boardIds) known[id]=1;
  const fullDeck=[];
  for(let id=8;id<60;id++) if(!known[id]) fullDeck.push(id);

  const opponents = players-1;
  const boardNeed = 5-boardIds.length;
  const need = boardNeed + opponents*2;
  const n = fullDeck.length;
  let wins=0, ties=0;
  const hero7 = new Array(7);
  const opp7  = new Array(7);

  for(let it=0; it<iters; it++){
    for(let i=0;i<need;i++){
      const j = i + Math.floor(rng()*(n-i));
      const tmp=fullDeck[i]; fullDeck[i]=fullDeck[j]; fullDeck[j]=tmp;
    }
    // hero 7
    let hi=0;
    for(const id of heroIds) hero7[hi++]=id;
    for(const id of boardIds) hero7[hi++]=id;
    for(let i=0;i<boardNeed;i++) hero7[hi++]=fullDeck[i];
    const heroScore = evaluate7(hero7);

    let beaten=false, tiedWith=0, idx=boardNeed;
    for(let o=0;o<opponents;o++){
      let oi=0;
      opp7[oi++]=fullDeck[idx++]; opp7[oi++]=fullDeck[idx++];
      for(const id of boardIds) opp7[oi++]=id;
      for(let i=0;i<boardNeed;i++) opp7[oi++]=fullDeck[i];
      const os=evaluate7(opp7);
      if(os>heroScore){ beaten=true; break; }
      else if(os===heroScore) tiedWith++;
    }
    if(beaten) continue;
    if(tiedWith>0) ties++; else wins++;
  }
  return { win:wins/iters, tie:ties/iters, equity:(wins+ties*0.5)/iters };
}

// Decision logic (mirrors index.html decide()).
export function decide(eq, players, pot, toCall){
  const fairShare = 1/players;
  if(toCall>0){
    const potOdds = toCall/(pot+toCall);
    if(eq < potOdds) return 'FOLD';
    if(eq > 0.66)    return 'RAISE';
    return 'CALL';
  }
  if(eq >= 0.58)      return 'BET';
  if(eq >= fairShare) return 'BET';   // small value bet
  return 'CHECK';
}

// Seedable RNG (mulberry32) for reproducible flip tests.
export function mulberry32(a){
  return function(){
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
