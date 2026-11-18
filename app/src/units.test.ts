import { describe, expect, it } from "vitest";
import { formatUnits, parseUnits } from "./units";

describe("units", () => {
  it("parses exact decimals", () => {
    expect(parseUnits("1.5", 8)).toBe(150000000n);
    expect(parseUnits("0.00000001", 8)).toBe(1n);
    expect(parseUnits("12", 6)).toBe(12000000n);
    expect(parseUnits(".5", 2)).toBe(50n);
  });
  it("rejects bad input", () => {
    for (const bad of ["", ".", "-1", "1e5", "1.234567890", "abc", "1,5", "1..2", "0x10"]) {
      expect(parseUnits(bad, 8)).toBeNull();
    }
    expect(parseUnits("1.123", 2)).toBeNull();
  });
  it("formats without float error", () => {
    expect(formatUnits(150000000n, 8)).toBe("1.5");
    expect(formatUnits(1n, 8, 8)).toBe("0.00000001");
    expect(formatUnits(1n, 8)).toBe("<0.000001"); // never shows a non-zero amount as 0
    expect(formatUnits(0n, 8)).toBe("0");
    expect(formatUnits(123456789012345678n, 8, 4)).toBe("1234567890.1234");
  });
  it("round trips", () => {
    for (const s of ["0.1", "123.456", "9999999999.99999999"]) {
      expect(formatUnits(parseUnits(s, 8)!, 8, 8)).toBe(s);
    }
  });
});
