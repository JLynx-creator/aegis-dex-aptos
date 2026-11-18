import { describe, expect, it } from "vitest";
import { AegisClient } from "../src/client";
import { parseAegisAbort, AEGIS_ERRORS } from "../src/errors";

const ADDR = "0xcafe";
const A = "0xaaa";
const B = "0xbbb";
const client = new AegisClient({} as never, ADDR);
const pool = { exists: true, reserveA: 1_000_000_000n, reserveB: 1_000_000_000n, lpSupply: 1_000_000_000n };

describe("payload builders", () => {
  it("swap payload carries min-out with slippage and a future deadline", () => {
    const { payload, expectedOut, minOut } = client.swapExactIn(A, B, 1_000_000n, 10n ** 9n, 10n ** 9n, { slippageBps: 100 });
    expect(payload.function).toBe("0xcafe::amm::swap_exact_in");
    expect(minOut).toBe((expectedOut * 9900n) / 10000n);
    const args = payload.functionArguments as string[];
    expect(args.slice(0, 4)).toEqual([A, B, "1000000", minOut.toString()]);
    expect(Number(args[4])).toBeGreaterThan(Date.now() / 1000);
  });
  it("swap with zero rounded output is refused client-side", () => {
    expect(() => client.swapExactIn(A, B, 1n, 10n ** 9n, 1_000n)).toThrow();
  });
  it("add liquidity sets minimums from the ratio-matched amounts", () => {
    const p = client.addLiquidity(A, B, 1_000_000n, 9_000_000n, pool, { slippageBps: 50 });
    const args = p.functionArguments as string[];
    expect(args.slice(2, 4)).toEqual(["1000000", "9000000"]);
    expect(args.slice(4, 6)).toEqual(["995000", "995000"]); // ratio 1:1 => takes 1e6/1e6
  });
  it("add liquidity to a missing pool is refused", () => {
    expect(() => client.addLiquidity(A, B, 1n, 1n, { ...pool, exists: false })).toThrow();
  });
  it("remove liquidity builds sane minimums", () => {
    const p = client.removeLiquidity(A, B, 500_000_000n, pool, { slippageBps: 0 });
    expect((p.functionArguments as string[]).slice(2, 5)).toEqual(["500000000", "500000000", "500000000"]);
  });
  it("rejects values outside u64", () => {
    expect(() => client.swapExactIn(A, B, 2n ** 64n, 10n ** 9n, 10n ** 9n)).toThrow();
  });
});

describe("error mapping", () => {
  it("parses Move abort strings", () => {
    const s = "Move abort in 0xcafe::amm: E_INSUFFICIENT_OUTPUT(0x6): ...";
    expect(parseAegisAbort(s)?.code).toBe(6);
  });
  it("returns null for unrelated errors", () => {
    expect(parseAegisAbort("Out of gas")).toBeNull();
    expect(parseAegisAbort(undefined)).toBeNull();
  });
  it("covers all 17 abort codes", () => {
    for (let i = 1; i <= 17; i++) expect(AEGIS_ERRORS[i]).toBeDefined();
  });
});
