/* KombatSim — JavaScript port of src/KombatSim.sol (bit-for-bit).
   Works in browsers and Node (no dependencies: includes a tiny keccak-256). */
(function (root) {
  // ---------- keccak-256 (BigInt lanes, rate 136) ----------
  const RC = [
    0x0000000000000001n,0x0000000000008082n,0x800000000000808an,0x8000000080008000n,0x000000000000808bn,0x0000000080000001n,
    0x8000000080008081n,0x8000000000008009n,0x000000000000008an,0x0000000000000088n,0x0000000080008009n,0x000000008000000an,
    0x000000008000808bn,0x800000000000008bn,0x8000000000008089n,0x8000000000008003n,0x8000000000008002n,0x8000000000000080n,
    0x000000000000800an,0x800000008000000an,0x8000000080008081n,0x8000000000008080n,0x0000000080000001n,0x8000000080008008n];
  const ROT=[0,1,62,28,27,36,44,6,55,20,3,10,43,25,39,41,45,15,21,8,18,2,61,56,14];
  const PI=[0,10,20,5,15,16,1,11,21,6,7,17,2,12,22,23,8,18,3,13,14,24,9,19,4];
  const M64=(1n<<64n)-1n;
  const rotl=(x,n)=>n===0?x:(((x<<BigInt(n))|(x>>BigInt(64-n)))&M64);
  function keccakF(s){
    for(let r=0;r<24;r++){
      const C=new Array(5);for(let x=0;x<5;x++)C[x]=s[x]^s[x+5]^s[x+10]^s[x+15]^s[x+20];
      for(let x=0;x<5;x++){const d=C[(x+4)%5]^rotl(C[(x+1)%5],1);for(let y=0;y<25;y+=5)s[x+y]^=d;}
      const B=new Array(25);for(let i=0;i<25;i++)B[PI[i]]=rotl(s[i],ROT[i]);
      for(let y=0;y<25;y+=5)for(let x=0;x<5;x++)s[y+x]=B[y+x]^((~B[y+(x+1)%5])&M64&B[y+(x+2)%5]);
      s[0]^=RC[r];
    }
  }
  function keccak256(bytes){ // Uint8Array -> Uint8Array(32)
    const s=new Array(25).fill(0n); const rate=136;
    const padded=new Uint8Array(Math.ceil((bytes.length+1)/rate)*rate); padded.set(bytes);
    padded[bytes.length]^=0x01; padded[padded.length-1]^=0x80;
    for(let off=0;off<padded.length;off+=rate){
      for(let i=0;i<rate/8;i++){let v=0n;for(let b=7;b>=0;b--)v=(v<<8n)|BigInt(padded[off+i*8+b]);s[i]^=v;}
      keccakF(s);
    }
    const out=new Uint8Array(32);for(let i=0;i<4;i++){let v=s[i];for(let b=0;b<8;b++){out[i*8+b]=Number(v&0xffn);v>>=8n;}}
    return out;
  }
  const hexToBytes=h=>{h=h.startsWith("0x")?h.slice(2):h;const o=new Uint8Array(h.length/2);for(let i=0;i<o.length;i++)o[i]=parseInt(h.substr(i*2,2),16);return o;};
  const bytesToBig=b=>{let v=0n;for(const x of b)v=(v<<8n)|BigInt(x);return v;};
  const u256=(n)=>{const o=new Uint8Array(32);let v=BigInt(n);for(let i=31;i>=0;i--){o[i]=Number(v&0xffn);v>>=8n;}return o;};

  // ---------- sim (mirror of KombatSim.sol) ----------
  const ARENA_NAP=0, ARENA_JOG=1, ARENA_ZOOMIES=2, MAX_EXCHANGES=24;
  function statsFor(level){const l=level===0?1:(level>10?10:level);return {hp:100+(l-1)*35,light:6+2*l,heavy:13+3*l,special:28+6*l};}
  // roll(seed,i) = keccak256(abi.encodePacked(bytes32 seed, uint256 i)) % 1000
  function roll(seedHex,i){const b=new Uint8Array(64);b.set(hexToBytes(seedHex),0);b.set(u256(i),32);return Number(bytesToBig(keccak256(b))%1000n);}
  const cap=v=>v>100?100:v;
  function pick(seed,i,meter){const x=roll(seed,i);if(meter>=100&&x<600)return 3;if(x<550)return 0;if(x<850)return 1;return 2;}
  function strike(atk,action,defAction,arena,dmgMul,seed,n){
    if(action===2)return {dmg:0,gAtk:0,gDef:0,ev:"block"};
    const hitRoll=roll(seed,n);const hitChance=action===0?780:(action===1?640:900);
    if(hitRoll>=hitChance)return {dmg:0,gAtk:2,gDef:0,ev:"whiff"};
    const base=action===0?atk.light:(action===1?atk.heavy:atk.special);
    let d=base*dmgMul;let crit=false;
    if(arena!==ARENA_NAP&&roll(seed,n+1)<150){d=Math.floor(d*3/2);crit=true;}
    const blocked=defAction===2;
    if(blocked)d=Math.floor((d+3)/4);
    return {dmg:d,gAtk:blocked?4:(action===0?12:(action===1?18:0)),gDef:6,ev:blocked?"blocked":(crit?"crit":"hit")};
  }
  function fight(levelA,levelB,arena,seedHex){
    const a=statsFor(levelA),b=statsFor(levelB);let hpA=a.hp,hpB=b.hp,mA=0,mB=0,n=0;
    const trickle=arena===ARENA_ZOOMIES?22:(arena===ARENA_JOG?7:0);const dmgMul=arena===ARENA_ZOOMIES?2:1;
    const log=[];let ex;
    for(ex=0;ex<MAX_EXCHANGES;ex++){
      mA=cap(mA+trickle);mB=cap(mB+trickle);
      const actA=pick(seedHex,n++,mA);const actB=pick(seedHex,n++,mB);
      const sA=strike(a,actA,actB,arena,dmgMul,seedHex,n);n+=2;
      const sB=strike(b,actB,actA,arena,dmgMul,seedHex,n);n+=2;
      if(actA===3)mA=0;if(actB===3)mB=0;
      mA=cap(mA+sA.gAtk+sB.gDef);mB=cap(mB+sA.gDef+sB.gAtk);
      hpB-=sA.dmg;hpA-=sB.dmg;
      log.push({actA,actB,dmgToB:sA.dmg,dmgToA:sB.dmg,evA:sA.ev,evB:sB.ev,hpA:Math.max(0,hpA),hpB:Math.max(0,hpB),mA,mB});
      if(hpA<=0||hpB<=0){ex++;break;}
    }
    const fa=hpA<0?0:hpA,fb=hpB<0?0:hpB;
    const winner=fa===fb?2:(fa>fb?0:1);
    return {winner,hpA:fa,hpB:fb,exchanges:ex,log,arena,levelA,levelB,seed:seedHex,maxA:a.hp,maxB:b.hp};
  }
  const api={keccak256,statsFor,roll,fight,ARENA_NAP,ARENA_JOG,ARENA_ZOOMIES,MAX_EXCHANGES};
  if(typeof module!=="undefined"&&module.exports)module.exports=api;else root.KombatSim=api;
})(typeof window!=="undefined"?window:globalThis);
