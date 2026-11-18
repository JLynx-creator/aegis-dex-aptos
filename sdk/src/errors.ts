/** Abort codes of aegis::amm (see top of sources/amm.move). */
export const AEGIS_ERRORS: Record<number, { name: string; message: string }> = {
  1: { name: "E_IDENTICAL_TOKENS", message: "Choose two different tokens." },
  2: { name: "E_POOL_EXISTS", message: "A pool for this pair already exists." },
  3: { name: "E_POOL_NOT_FOUND", message: "No pool exists for this pair yet." },
  4: { name: "E_ZERO_AMOUNT", message: "Amount must be greater than zero." },
  5: { name: "E_EXPIRED", message: "Transaction deadline passed. Try again." },
  6: { name: "E_INSUFFICIENT_OUTPUT", message: "Price moved: output is below your minimum. Increase slippage or retry." },
  7: { name: "E_INSUFFICIENT_AMOUNT_MIN", message: "Amounts fell below your minimums. Increase slippage or retry." },
  8: { name: "E_INSUFFICIENT_LIQUIDITY_MINTED", message: "Deposit too small to mint any LP tokens." },
  9: { name: "E_INSUFFICIENT_LIQUIDITY_BURNED", message: "Withdrawal too small to return any tokens." },
  10: { name: "E_LOCKED", message: "Pool is busy. Retry." },
  11: { name: "E_RESERVE_OVERFLOW", message: "Amount would overflow the pool's reserves." },
  12: { name: "E_UNEXPECTED_TRANSFER_AMOUNT", message: "This token does not transfer exact amounts and is unsupported." },
  13: { name: "E_INVALID_STATE", message: "Pool is in an unexpected state. Do not retry; contact the team." },
  14: { name: "E_NOT_DEPLOYER", message: "Initialisation must be done by the publisher." },
  15: { name: "E_INSUFFICIENT_INITIAL_LIQUIDITY", message: "First deposit is too small (needs sqrt(a*b) > 1000)." },
  16: { name: "E_K_INVARIANT", message: "Invariant check failed. Do not retry; contact the team." },
  17: { name: "E_INSUFFICIENT_RESERVES", message: "Pool has no liquidity." },
};

/** Extract an Aegis abort code from a VM status string such as "Move abort in 0x..::amm: E_...(0x6)". */
export function parseAegisAbort(vmStatus: string | undefined | null): { code: number; name: string; message: string } | null {
  if (!vmStatus) return null;
  const m = /::amm: .*?\(0x([0-9a-fA-F]+)\)/.exec(vmStatus) ?? /::amm.*?abort.*?(?:code[: ]+)(\d+)/i.exec(vmStatus);
  if (!m) return null;
  const raw = m[0].includes("(0x") ? parseInt(m[1], 16) : parseInt(m[1], 10);
  const info = AEGIS_ERRORS[raw];
  return info ? { code: raw, ...info } : null;
}
