/**
 * Pure bigint mirrors of the on-chain math in aegis::amm. Keep in sync with sources/amm.move.
 * All functions floor, exactly like the contract.
 */
export const FEE_NUMERATOR = 997n;
export const FEE_DENOMINATOR = 1000n;
export const MINIMUM_LIQUIDITY = 1000n;
export const MAX_U64 = 18446744073709551615n;
export const BPS = 10000n;

export function isqrt(n: bigint): bigint {
  if (n < 0n) throw new RangeError("isqrt of negative");
  if (n < 2n) return n;
  let x = n;
  let y = (x + 1n) / 2n;
  while (y < x) {
    x = y;
    y = (x + n / x) / 2n;
  }
  return x;
}

/** out = in*997*rOut / (rIn*1000 + in*997) */
export function getAmountOut(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): bigint {
  if (amountIn <= 0n) throw new RangeError("amountIn must be > 0");
  if (reserveIn <= 0n || reserveOut <= 0n) throw new RangeError("empty reserves");
  const inWithFee = amountIn * FEE_NUMERATOR;
  return (inWithFee * reserveOut) / (reserveIn * FEE_DENOMINATOR + inWithFee);
}

/** Proportional amount: a * reserveB / reserveA */
export function quote(amountA: bigint, reserveA: bigint, reserveB: bigint): bigint {
  if (amountA <= 0n) throw new RangeError("amount must be > 0");
  if (reserveA <= 0n || reserveB <= 0n) throw new RangeError("empty reserves");
  return (amountA * reserveB) / reserveA;
}

/** Minimum acceptable amount for a given slippage tolerance in basis points (floor). */
export function applySlippage(amount: bigint, slippageBps: number): bigint {
  if (!Number.isInteger(slippageBps) || slippageBps < 0 || slippageBps > 10000) {
    throw new RangeError("slippageBps must be an integer in [0, 10000]");
  }
  return (amount * (BPS - BigInt(slippageBps))) / BPS;
}

/** Price impact of a swap in basis points relative to the pre-trade spot price (floor). */
export function priceImpactBps(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): bigint {
  const out = getAmountOut(amountIn, reserveIn, reserveOut);
  // spot out (no fee, no impact) = amountIn * reserveOut / reserveIn
  const ideal = (amountIn * reserveOut) / reserveIn;
  if (ideal === 0n) return BPS;
  const worse = ideal > out ? ideal - out : 0n;
  return (worse * BPS) / ideal;
}

export interface AddLiquidityQuote {
  amountA: bigint;
  amountB: bigint;
  lpMinted: bigint;
}

/**
 * Mirrors add_liquidity. `supply` is the LP total supply (incl. locked minimum), 0 for a new pool.
 * Throws where the contract would abort.
 */
export function quoteAddLiquidity(
  desiredA: bigint,
  desiredB: bigint,
  reserveA: bigint,
  reserveB: bigint,
  supply: bigint,
): AddLiquidityQuote {
  if (desiredA <= 0n || desiredB <= 0n) throw new RangeError("amounts must be > 0");
  let a: bigint;
  let b: bigint;
  if (supply === 0n) {
    a = desiredA;
    b = desiredB;
    const root = isqrt(a * b);
    if (root <= MINIMUM_LIQUIDITY) throw new RangeError("initial liquidity too small");
    return { amountA: a, amountB: b, lpMinted: root - MINIMUM_LIQUIDITY };
  }
  const optB = quote(desiredA, reserveA, reserveB);
  if (optB <= desiredB) {
    a = desiredA;
    b = optB;
  } else {
    a = quote(desiredB, reserveB, reserveA);
    b = desiredB;
  }
  if (a <= 0n || b <= 0n) throw new RangeError("amounts round to zero");
  const l0 = (a * supply) / reserveA;
  const l1 = (b * supply) / reserveB;
  const lp = l0 < l1 ? l0 : l1;
  if (lp <= 0n) throw new RangeError("liquidity minted rounds to zero");
  return { amountA: a, amountB: b, lpMinted: lp };
}

export interface RemoveLiquidityQuote {
  amountA: bigint;
  amountB: bigint;
}

export function quoteRemoveLiquidity(
  lpAmount: bigint,
  reserveA: bigint,
  reserveB: bigint,
  supply: bigint,
): RemoveLiquidityQuote {
  if (lpAmount <= 0n || supply <= 0n || lpAmount > supply) throw new RangeError("invalid lp amount");
  const a = (lpAmount * reserveA) / supply;
  const b = (lpAmount * reserveB) / supply;
  if (a <= 0n || b <= 0n) throw new RangeError("payout rounds to zero");
  return { amountA: a, amountB: b };
}
