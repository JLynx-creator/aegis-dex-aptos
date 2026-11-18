import type { Aptos, InputEntryFunctionData } from "@aptos-labs/ts-sdk";
import { applySlippage, getAmountOut, quoteAddLiquidity, quoteRemoveLiquidity } from "./math.js";

const U64_MAX = 18446744073709551615n;

function u64(v: bigint, label: string): string {
  if (v < 0n || v > U64_MAX) throw new RangeError(`${label} is outside u64 range`);
  return v.toString();
}

export interface PoolInfo {
  exists: boolean;
  reserveA: bigint;
  reserveB: bigint;
  lpSupply: bigint;
  lpToken?: string;
}

export interface TxOptions {
  /** Slippage tolerance in basis points (30 = 0.30 %). Default 50. */
  slippageBps?: number;
  /** Seconds from now until the transaction expires. Default 600. */
  deadlineSecs?: number;
}

/**
 * Thin typed wrapper around the aegis::amm entry functions and views. It only builds payloads and reads
 * state; signing is left to the caller's wallet.
 */
export class AegisClient {
  constructor(
    private readonly aptos: Aptos,
    /** Address the aegis package is published at. */
    public readonly moduleAddress: string,
  ) {}

  private fn(name: string): `${string}::${string}::${string}` {
    return `${this.moduleAddress}::amm::${name}`;
  }

  private deadline(opts?: TxOptions): string {
    const secs = opts?.deadlineSecs ?? 600;
    return String(Math.floor(Date.now() / 1000) + secs);
  }

  // ---------------------------------------------------------------- views
  async poolExists(tokenA: string, tokenB: string): Promise<boolean> {
    const [ok] = await this.aptos.view<[boolean]>({
      payload: { function: this.fn("pool_exists"), functionArguments: [tokenA, tokenB] },
    });
    return ok;
  }

  async getPool(tokenA: string, tokenB: string): Promise<PoolInfo> {
    if (!(await this.poolExists(tokenA, tokenB))) {
      return { exists: false, reserveA: 0n, reserveB: 0n, lpSupply: 0n };
    }
    const [reserves, supply, lp] = await Promise.all([
      this.aptos.view<[string, string]>({ payload: { function: this.fn("get_reserves"), functionArguments: [tokenA, tokenB] } }),
      this.aptos.view<[string]>({ payload: { function: this.fn("lp_total_supply"), functionArguments: [tokenA, tokenB] } }),
      this.aptos.view<[{ inner: string }]>({ payload: { function: this.fn("lp_token"), functionArguments: [tokenA, tokenB] } }),
    ]);
    return {
      exists: true,
      reserveA: BigInt(reserves[0]),
      reserveB: BigInt(reserves[1]),
      lpSupply: BigInt(supply[0]),
      lpToken: lp[0].inner,
    };
  }

  // ------------------------------------------------------------- payloads
  createPool(tokenA: string, tokenB: string): InputEntryFunctionData {
    return { function: this.fn("create_pool"), functionArguments: [tokenA, tokenB] };
  }

  /** Build an add-liquidity payload. The pool state is used only to compute sensible minimums. */
  addLiquidity(
    tokenA: string,
    tokenB: string,
    desiredA: bigint,
    desiredB: bigint,
    pool: PoolInfo,
    opts?: TxOptions,
  ): InputEntryFunctionData {
    if (!pool.exists) throw new Error("Pool does not exist; create it first");
    const q = quoteAddLiquidity(desiredA, desiredB, pool.reserveA, pool.reserveB, pool.lpSupply);
    const bps = opts?.slippageBps ?? 50;
    return {
      function: this.fn("add_liquidity"),
      functionArguments: [
        tokenA, tokenB,
        u64(desiredA, "desiredA"), u64(desiredB, "desiredB"),
        u64(applySlippage(q.amountA, bps), "minA"), u64(applySlippage(q.amountB, bps), "minB"),
        this.deadline(opts),
      ],
    };
  }

  removeLiquidity(
    tokenA: string,
    tokenB: string,
    lpAmount: bigint,
    pool: PoolInfo,
    opts?: TxOptions,
  ): InputEntryFunctionData {
    const q = quoteRemoveLiquidity(lpAmount, pool.reserveA, pool.reserveB, pool.lpSupply);
    const bps = opts?.slippageBps ?? 50;
    return {
      function: this.fn("remove_liquidity"),
      functionArguments: [
        tokenA, tokenB, u64(lpAmount, "lpAmount"),
        u64(applySlippage(q.amountA, bps), "minA"), u64(applySlippage(q.amountB, bps), "minB"),
        this.deadline(opts),
      ],
    };
  }

  /** Exact-input swap. `reserveIn`/`reserveOut` come from the pool in the (tokenIn, tokenOut) orientation. */
  swapExactIn(
    tokenIn: string,
    tokenOut: string,
    amountIn: bigint,
    reserveIn: bigint,
    reserveOut: bigint,
    opts?: TxOptions,
  ): { payload: InputEntryFunctionData; expectedOut: bigint; minOut: bigint } {
    const expectedOut = getAmountOut(amountIn, reserveIn, reserveOut);
    const minOut = applySlippage(expectedOut, opts?.slippageBps ?? 50);
    if (minOut <= 0n) throw new RangeError("Output rounds to zero");
    return {
      expectedOut,
      minOut,
      payload: {
        function: this.fn("swap_exact_in"),
        functionArguments: [tokenIn, tokenOut, u64(amountIn, "amountIn"), u64(minOut, "minOut"), this.deadline(opts)],
      },
    };
  }
}
