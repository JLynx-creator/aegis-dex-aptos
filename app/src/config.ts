import { Network } from "@aptos-labs/ts-sdk";

export interface TokenInfo {
  symbol: string;
  name: string;
  address: string;
  decimals: number;
}

export interface AppConfig {
  network: Network;
  networkName: "testnet" | "mainnet";
  aegisAddress: string;
  tokens: TokenInfo[];
}

const ADDR = /^0x[0-9a-fA-F]{1,64}$/;

/** Reads and validates build-time env. Throws a readable error if misconfigured. */
export function loadConfig(env: Record<string, string | undefined> = import.meta.env): AppConfig {
  const name = env.VITE_NETWORK;
  if (name !== "testnet" && name !== "mainnet") throw new Error("VITE_NETWORK must be 'testnet' or 'mainnet'");
  const aegisAddress = env.VITE_AEGIS_ADDRESS ?? "";
  if (!ADDR.test(aegisAddress)) throw new Error("VITE_AEGIS_ADDRESS is missing or not a valid address");
  let tokens: TokenInfo[];
  try {
    tokens = JSON.parse(env.VITE_TOKENS ?? "[]");
  } catch {
    throw new Error("VITE_TOKENS is not valid JSON");
  }
  if (!Array.isArray(tokens) || tokens.length < 2) throw new Error("VITE_TOKENS needs at least two tokens");
  const seen = new Set<string>();
  for (const t of tokens) {
    if (!t.symbol || !ADDR.test(t.address) || !Number.isInteger(t.decimals) || t.decimals < 0 || t.decimals > 18) {
      throw new Error(`Invalid token entry: ${JSON.stringify(t)}`);
    }
    const key = t.address.toLowerCase();
    if (seen.has(key)) throw new Error(`Duplicate token address: ${t.address}`);
    seen.add(key);
  }
  return {
    network: name === "mainnet" ? Network.MAINNET : Network.TESTNET,
    networkName: name,
    aegisAddress,
    tokens,
  };
}
