import { describe, expect, it } from "vitest";
import { loadConfig } from "./config";

const good = {
  VITE_NETWORK: "testnet",
  VITE_AEGIS_ADDRESS: "0xcafe",
  VITE_TOKENS: JSON.stringify([
    { symbol: "A", name: "A", address: "0xa1", decimals: 8 },
    { symbol: "B", name: "B", address: "0xb2", decimals: 6 },
  ]),
};

describe("loadConfig", () => {
  it("accepts a valid config", () => {
    expect(loadConfig(good).tokens).toHaveLength(2);
  });
  it("rejects bad network, address, json, duplicates, single token", () => {
    expect(() => loadConfig({ ...good, VITE_NETWORK: "devnet" })).toThrow();
    expect(() => loadConfig({ ...good, VITE_AEGIS_ADDRESS: "cafe" })).toThrow();
    expect(() => loadConfig({ ...good, VITE_TOKENS: "nope" })).toThrow();
    expect(() => loadConfig({ ...good, VITE_TOKENS: JSON.stringify([{ symbol: "A", name: "A", address: "0xa1", decimals: 8 }]) })).toThrow();
    expect(() =>
      loadConfig({ ...good, VITE_TOKENS: JSON.stringify([
        { symbol: "A", name: "A", address: "0xa1", decimals: 8 },
        { symbol: "B", name: "B", address: "0xA1", decimals: 8 },
      ]) }),
    ).toThrow();
  });
});
