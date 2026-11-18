/** Strict decimal <-> base-unit conversion. Never goes through floating point. */
export function parseUnits(input: string, decimals: number): bigint | null {
  const s = input.trim();
  if (!/^\d*\.?\d*$/.test(s) || s === "" || s === ".") return null;
  const [whole, frac = ""] = s.split(".");
  if (frac.length > decimals) return null;
  const v = BigInt((whole || "0") + frac.padEnd(decimals, "0"));
  return v;
}

export function formatUnits(value: bigint, decimals: number, maxFrac = 6): string {
  const base = 10n ** BigInt(decimals);
  const whole = value / base;
  let frac = (value % base).toString().padStart(decimals, "0").slice(0, maxFrac).replace(/0+$/, "");
  if (frac) return `${whole}.${frac}`;
  // Never display a non-zero amount as "0": show a "less than" marker instead.
  if (whole === 0n && value > 0n && maxFrac > 0) return `<0.${"0".repeat(maxFrac - 1)}1`;
  return whole.toString();
}
