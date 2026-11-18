import { describe, expect, it } from "vitest";
import {
  applySlippage, getAmountOut, isqrt, priceImpactBps, quote,
  quoteAddLiquidity, quoteRemoveLiquidity, MAX_U64,
} from "../src/math";

// xorshift for deterministic pseudo-random tests
function rng(seed: bigint) {
  let s = seed;
  return (bound: bigint) => {
    s = (s * 6364136223846793005n + 1442695040888963407n) % 2n ** 64n;
    return (s >> 17n) % bound;
  };
}

describe("getAmountOut (mirrors Move test vectors)", () => {
  it("matches the on-chain known vector: 1000 in on 100000/100000 -> 987", () => {
    expect(getAmountOut(1000n, 100000n, 100000n)).toBe(987n);
  });
  it("rejects zero input and empty reserves", () => {
    expect(() => getAmountOut(0n, 1n, 1n)).toThrow();
    expect(() => getAmountOut(1n, 0n, 1n)).toThrow();
  });
  it("never drains the pool and k never decreases (randomized)", () => {
    const r = rng(7n);
    for (let i = 0; i < 5000; i++) {
      const rin = 1n + r(MAX_U64 / 2n);
      const rout = 1n + r(MAX_U64);
      const ain = 1n + r(MAX_U64 - rin);
      const out = getAmountOut(ain, rin, rout);
      expect(out).toBeLessThan(rout);
      expect((rin + ain) * (rout - out)).toBeGreaterThanOrEqual(rin * rout);
    }
  });
  it("round trip never profits", () => {
    const r = rng(11n);
    for (let i = 0; i < 2000; i++) {
      const ra = 1_000_000n + r(10n ** 15n);
      const rb = 1_000_000n + r(10n ** 15n);
      const a = 1000n + r(ra / 2n);
      const b = getAmountOut(a, ra, rb);
      if (b === 0n) continue;
      const back = getAmountOut(b, rb - b, ra + a);
      expect(back).toBeLessThan(a);
    }
  });
});

describe("liquidity quotes", () => {
  it("first deposit: sqrt(a*b) - 1000", () => {
    const q = quoteAddLiquidity(1_000_000n, 4_000_000n, 0n, 0n, 0n);
    expect(q.lpMinted).toBe(1_999_000n);
  });
  it("first deposit at the minimum aborts", () => {
    expect(() => quoteAddLiquidity(1000n, 1000n, 0n, 0n, 0n)).toThrow();
  });
  it("second deposit takes only ratio-matched amounts (matches Move test)", () => {
    const q = quoteAddLiquidity(1_000_000n, 9_000_000n, 1_000_000n, 4_000_000n, 2_000_000n);
    expect(q).toEqual({ amountA: 1_000_000n, amountB: 4_000_000n, lpMinted: 2_000_000n });
  });
  it("remove returns pro-rata floor amounts (matches Move test)", () => {
    const q = quoteRemoveLiquidity(1_999_000n, 1_000_000n, 4_000_000n, 2_000_000n);
    expect(q).toEqual({ amountA: 999_500n, amountB: 3_998_000n });
  });
  it("add then remove never returns more than deposited (randomized)", () => {
    const r = rng(99n);
    for (let i = 0; i < 3000; i++) {
      const ra = 10n ** 6n + r(10n ** 14n);
      const rb = 10n ** 6n + r(10n ** 14n);
      const supply = isqrt(ra * rb);
      const da = 1000n + r(ra);
      const db = 1000n + r(rb);
      let q;
      try { q = quoteAddLiquidity(da, db, ra, rb, supply); } catch { continue; }
      const rem = quoteRemoveLiquidity(q.lpMinted, ra + q.amountA, rb + q.amountB, supply + q.lpMinted);
      expect(rem.amountA).toBeLessThanOrEqual(q.amountA);
      expect(rem.amountB).toBeLessThanOrEqual(q.amountB);
    }
  });
});

describe("helpers", () => {
  it("applySlippage floors and validates", () => {
    expect(applySlippage(10_000n, 50)).toBe(9_950n);
    expect(applySlippage(999n, 100)).toBe(989n);
    expect(() => applySlippage(1n, -1)).toThrow();
    expect(() => applySlippage(1n, 10001)).toThrow();
    expect(() => applySlippage(1n, 0.5)).toThrow();
  });
  it("isqrt is exact", () => {
    for (const n of [0n, 1n, 2n, 3n, 4n, 15n, 16n, 10n ** 30n, MAX_U64 * MAX_U64]) {
      const s = isqrt(n);
      expect(s * s).toBeLessThanOrEqual(n);
      expect((s + 1n) * (s + 1n)).toBeGreaterThan(n);
    }
  });
  it("quote is proportional", () => {
    expect(quote(1000n, 2000n, 6000n)).toBe(3000n);
  });
  it("price impact grows with trade size", () => {
    const small = priceImpactBps(1_000n, 10n ** 9n, 10n ** 9n);
    const big = priceImpactBps(10n ** 8n, 10n ** 9n, 10n ** 9n);
    expect(big).toBeGreaterThan(small);
  });
});
