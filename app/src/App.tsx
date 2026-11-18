import { useCallback, useEffect, useMemo, useState } from "react";
import { Aptos, AptosConfig, type InputEntryFunctionData } from "@aptos-labs/ts-sdk";
import { useWallet } from "@aptos-labs/wallet-adapter-react";
import {
  AegisClient, parseAegisAbort, priceImpactBps, quote, quoteAddLiquidity, quoteRemoveLiquidity,
  getAmountOut, applySlippage, type PoolInfo,
} from "@aegis-dex/sdk";
import type { AppConfig, TokenInfo } from "./config";
import { formatUnits, parseUnits } from "./units";

const IMPACT_WARN_BPS = 500n; // 5 %
const IMPACT_BLOCK_BPS = 1500n; // 15 %
const MAX_SLIPPAGE_BPS = 5000; // 50 %

// ---------------------------------------------------------------- hooks
function useBalance(aptos: Aptos, token: string | undefined, owner: string | undefined, tick: number) {
  const [bal, setBal] = useState<bigint | null>(null);
  useEffect(() => {
    let live = true;
    setBal(null);
    if (!token || !owner) return;
    aptos
      .view<[string]>({
        payload: {
          function: "0x1::primary_fungible_store::balance",
          typeArguments: ["0x1::fungible_asset::Metadata"],
          functionArguments: [owner, token],
        },
      })
      .then((r) => live && setBal(BigInt(r[0])))
      .catch(() => live && setBal(null));
    return () => { live = false; };
  }, [aptos, token, owner, tick]);
  return bal;
}

function usePool(client: AegisClient, a: string, b: string, tick: number) {
  const [pool, setPool] = useState<PoolInfo | null>(null);
  const [loading, setLoading] = useState(false);
  useEffect(() => {
    let live = true;
    setPool(null);
    if (a.toLowerCase() === b.toLowerCase()) return;
    setLoading(true);
    client.getPool(a, b)
      .then((p) => live && setPool(p))
      .catch(() => live && setPool(null))
      .finally(() => live && setLoading(false));
    return () => { live = false; };
  }, [client, a, b, tick]);
  return { pool, loading };
}

type TxState = { phase: "idle" | "pending" | "ok" | "error"; message?: string; hash?: string };

function useTx(aptos: Aptos, onDone: () => void) {
  const { signAndSubmitTransaction } = useWallet();
  const [state, setState] = useState<TxState>({ phase: "idle" });
  const run = useCallback(async (data: InputEntryFunctionData) => {
    setState({ phase: "pending", message: "Confirm in your wallet…" });
    try {
      const res = await signAndSubmitTransaction({ data });
      setState({ phase: "pending", message: "Waiting for confirmation…", hash: res.hash });
      await aptos.waitForTransaction({ transactionHash: res.hash });
      setState({ phase: "ok", message: "Success", hash: res.hash });
      onDone();
    } catch (e) {
      const raw = String((e as { message?: string })?.message ?? e);
      const mapped = parseAegisAbort(raw);
      setState({ phase: "error", message: mapped ? mapped.message : raw.slice(0, 300) });
    }
  }, [aptos, signAndSubmitTransaction, onDone]);
  return { state, run };
}

// ---------------------------------------------------------- components
function TxStatus({ s, network }: { s: TxState; network: string }) {
  if (s.phase === "idle") return null;
  return (
    <p className={`status ${s.phase}`}>
      {s.message}{" "}
      {s.hash && (
        <a href={`https://explorer.aptoslabs.com/txn/${s.hash}?network=${network}`} target="_blank" rel="noreferrer noopener">view</a>
      )}
    </p>
  );
}

function TokenSelect({ tokens, value, onChange, label }: { tokens: TokenInfo[]; value: number; onChange: (i: number) => void; label: string }) {
  return (
    <select aria-label={label} value={value} onChange={(e) => onChange(Number(e.target.value))}>
      {tokens.map((t, i) => <option key={t.address} value={i}>{t.symbol}</option>)}
    </select>
  );
}

function SlippageInput({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="row small">
      <span>Slippage %</span>
      {["0.1", "0.5", "1"].map((p) => (
        <button key={p} className={value === p ? "chip active" : "chip"} onClick={() => onChange(p)}>{p}</button>
      ))}
      <input className="tiny" aria-label="custom slippage percent" value={value} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}

function slippageToBps(s: string): number | null {
  if (!/^\d+(\.\d{1,2})?$/.test(s)) return null;
  const bps = Math.round(parseFloat(s) * 100);
  return bps >= 0 && bps <= MAX_SLIPPAGE_BPS ? bps : null;
}

function SwapCard({ cfg, aptos, client, owner }: { cfg: AppConfig; aptos: Aptos; client: AegisClient; owner?: string }) {
  const [tick, setTick] = useState(0);
  const [i, setI] = useState(0);
  const [o, setO] = useState(1);
  const [amt, setAmt] = useState("");
  const [slip, setSlip] = useState("0.5");
  const tin = cfg.tokens[i], tout = cfg.tokens[o];
  const { pool } = usePool(client, tin.address, tout.address, tick);
  const balIn = useBalance(aptos, tin.address, owner, tick);
  const balOut = useBalance(aptos, tout.address, owner, tick);
  const { state, run } = useTx(aptos, () => { setTick((t) => t + 1); setAmt(""); });

  const amountIn = parseUnits(amt, tin.decimals);
  const bps = slippageToBps(slip);
  const hasLiquidity = !!pool && pool.exists && pool.reserveA > 0n && pool.reserveB > 0n;

  let expectedOut = 0n, minOut = 0n, impact = 0n, problem: string | null = null;
  if (i === o) problem = "Select two different tokens";
  else if (!amt) problem = "Enter an amount";
  else if (amountIn === null || amountIn <= 0n) problem = "Invalid amount";
  else if (bps === null) problem = "Slippage must be 0–50 % (max 2 decimals)";
  else if (!pool) problem = "Loading pool…";
  else if (!hasLiquidity) problem = "No liquidity in this pool";
  else if (balIn !== null && amountIn > balIn) problem = `Insufficient ${tin.symbol} balance`;
  else {
    try {
      expectedOut = getAmountOut(amountIn, pool.reserveA, pool.reserveB);
      minOut = applySlippage(expectedOut, bps);
      impact = priceImpactBps(amountIn, pool.reserveA, pool.reserveB);
      if (expectedOut === 0n || minOut === 0n) problem = "Amount too small";
      else if (impact >= IMPACT_BLOCK_BPS) problem = "Price impact too high (≥ 15 %)";
    } catch (e) { problem = (e as Error).message; }
  }

  const submit = () => {
    if (problem || !pool || amountIn === null || bps === null) return;
    const { payload } = client.swapExactIn(tin.address, tout.address, amountIn, pool.reserveA, pool.reserveB, { slippageBps: bps });
    void run(payload);
  };

  return (
    <section className="card">
      <h2>Swap</h2>
      <div className="row">
        <input aria-label="amount in" inputMode="decimal" placeholder="0.0" value={amt} onChange={(e) => setAmt(e.target.value)} />
        <TokenSelect tokens={cfg.tokens} value={i} onChange={setI} label="token in" />
      </div>
      <p className="muted small">Balance: {balIn === null ? "—" : formatUnits(balIn, tin.decimals)} {tin.symbol}</p>
      <button className="flip" aria-label="flip tokens" onClick={() => { setI(o); setO(i); }}>⇅</button>
      <div className="row">
        <input aria-label="amount out" readOnly value={expectedOut ? formatUnits(expectedOut, tout.decimals, 8) : ""} placeholder="0.0" />
        <TokenSelect tokens={cfg.tokens} value={o} onChange={setO} label="token out" />
      </div>
      <p className="muted small">Balance: {balOut === null ? "—" : formatUnits(balOut, tout.decimals)} {tout.symbol}</p>
      <SlippageInput value={slip} onChange={setSlip} />
      {expectedOut > 0n && (
        <ul className="details small">
          <li>Fee: 0.30 % (stays in the pool for LPs)</li>
          <li>Minimum received: {formatUnits(minOut, tout.decimals, 8)} {tout.symbol}</li>
          <li className={impact >= IMPACT_WARN_BPS ? "warn" : ""}>Price impact: {(Number(impact) / 100).toFixed(2)} %</li>
        </ul>
      )}
      <button className="primary" disabled={!owner || !!problem || state.phase === "pending"} onClick={submit}>
        {!owner ? "Connect wallet" : problem ?? "Swap"}
      </button>
      <TxStatus s={state} network={cfg.networkName} />
    </section>
  );
}

function LiquidityCard({ cfg, aptos, client, owner }: { cfg: AppConfig; aptos: Aptos; client: AegisClient; owner?: string }) {
  const [tick, setTick] = useState(0);
  const [i, setI] = useState(0);
  const [j, setJ] = useState(1);
  const [mode, setMode] = useState<"add" | "remove">("add");
  const [amtA, setAmtA] = useState("");
  const [amtB, setAmtB] = useState("");
  const [pct, setPct] = useState(0);
  const [slip, setSlip] = useState("0.5");
  const ta = cfg.tokens[i], tb = cfg.tokens[j];
  const { pool, loading } = usePool(client, ta.address, tb.address, tick);
  const balA = useBalance(aptos, ta.address, owner, tick);
  const balB = useBalance(aptos, tb.address, owner, tick);
  const lpBal = useBalance(aptos, pool?.lpToken, owner, tick);
  const { state, run } = useTx(aptos, () => { setTick((t) => t + 1); setAmtA(""); setAmtB(""); setPct(0); });

  const bps = slippageToBps(slip);
  const live = !!pool && pool.exists && pool.lpSupply > 0n && pool.reserveA > 0n && pool.reserveB > 0n;

  const a = parseUnits(amtA, ta.decimals);
  let b = parseUnits(amtB, tb.decimals);
  if (live && a !== null && a > 0n) {
    try { b = quote(a, pool!.reserveA, pool!.reserveB); } catch { b = null; }
  }

  let problem: string | null = null;
  let action: (() => void) | null = null;
  if (i === j) problem = "Select two different tokens";
  else if (!owner) problem = "Connect wallet";
  else if (loading || !pool) problem = "Loading pool…";
  else if (!pool.exists) {
    problem = null;
    action = () => void run(client.createPool(ta.address, tb.address));
  } else if (bps === null) problem = "Slippage must be 0–50 % (max 2 decimals)";
  else if (mode === "add") {
    if (a === null || b === null || a <= 0n || b <= 0n) problem = "Enter amounts";
    else if (balA !== null && a > balA) problem = `Insufficient ${ta.symbol}`;
    else if (balB !== null && b > balB) problem = `Insufficient ${tb.symbol}`;
    else {
      try {
        quoteAddLiquidity(a, b, pool.reserveA, pool.reserveB, pool.lpSupply);
        action = () => void run(client.addLiquidity(ta.address, tb.address, a, b, pool, { slippageBps: bps }));
      } catch (e) { problem = (e as Error).message; }
    }
  } else {
    const lp = lpBal === null ? 0n : (lpBal * BigInt(pct)) / 100n;
    if (lp <= 0n) problem = "Choose an amount to withdraw";
    else {
      try {
        quoteRemoveLiquidity(lp, pool.reserveA, pool.reserveB, pool.lpSupply);
        action = () => void run(client.removeLiquidity(ta.address, tb.address, lp, pool, { slippageBps: bps }));
      } catch (e) { problem = (e as Error).message; }
    }
  }

  const removeQuote = (() => {
    if (!pool?.exists || !lpBal || pct === 0) return null;
    try { return quoteRemoveLiquidity((lpBal * BigInt(pct)) / 100n, pool.reserveA, pool.reserveB, pool.lpSupply); } catch { return null; }
  })();

  const label = !owner ? "Connect wallet" : pool && !pool.exists && i !== j ? "Create pool" : problem ?? (mode === "add" ? "Add liquidity" : "Remove liquidity");

  return (
    <section className="card">
      <h2>Liquidity</h2>
      <div className="row">
        <TokenSelect tokens={cfg.tokens} value={i} onChange={setI} label="token A" />
        <TokenSelect tokens={cfg.tokens} value={j} onChange={setJ} label="token B" />
      </div>
      {pool?.exists && (
        <p className="muted small">
          Reserves: {formatUnits(pool.reserveA, ta.decimals)} {ta.symbol} / {formatUnits(pool.reserveB, tb.decimals)} {tb.symbol}
          {lpBal !== null && pool.lpSupply > 0n && <> · Your share: {(Number((lpBal * 10000n) / pool.lpSupply) / 100).toFixed(2)} %</>}
        </p>
      )}
      {pool && !pool.exists && i !== j && <p className="muted small">No pool yet. Create it, then add the first liquidity (this sets the initial price).</p>}
      <div className="row small">
        <button className={mode === "add" ? "chip active" : "chip"} onClick={() => setMode("add")}>Add</button>
        <button className={mode === "remove" ? "chip active" : "chip"} onClick={() => setMode("remove")}>Remove</button>
      </div>
      {mode === "add" ? (
        <>
          <div className="row"><input aria-label="amount A" inputMode="decimal" placeholder="0.0" value={amtA} onChange={(e) => setAmtA(e.target.value)} /><span>{ta.symbol}</span></div>
          <div className="row">
            <input aria-label="amount B" inputMode="decimal" placeholder="0.0" readOnly={!!live}
              value={live ? (b !== null ? formatUnits(b, tb.decimals, 8) : "") : amtB} onChange={(e) => setAmtB(e.target.value)} />
            <span>{tb.symbol}</span>
          </div>
          {live && <p className="muted small">Amount B is set by the current pool ratio.</p>}
        </>
      ) : (
        <>
          <div className="row small">
            {[25, 50, 75, 100].map((p) => <button key={p} className={pct === p ? "chip active" : "chip"} onClick={() => setPct(p)}>{p}%</button>)}
          </div>
          <p className="muted small">LP balance: {lpBal === null ? "—" : formatUnits(lpBal, 8)}</p>
          {removeQuote && <p className="small">You receive ≈ {formatUnits(removeQuote.amountA, ta.decimals, 8)} {ta.symbol} + {formatUnits(removeQuote.amountB, tb.decimals, 8)} {tb.symbol}</p>}
        </>
      )}
      <SlippageInput value={slip} onChange={setSlip} />
      <button className="primary" disabled={!action || state.phase === "pending"} onClick={() => action?.()}>{label}</button>
      <TxStatus s={state} network={cfg.networkName} />
    </section>
  );
}

function short(a: string) { return `${a.slice(0, 6)}…${a.slice(-4)}`; }

export function App({ cfg }: { cfg: AppConfig }) {
  const { connected, account, wallets, connect, disconnect, network } = useWallet();
  const aptos = useMemo(() => new Aptos(new AptosConfig({ network: cfg.network })), [cfg.network]);
  const client = useMemo(() => new AegisClient(aptos, cfg.aegisAddress), [aptos, cfg.aegisAddress]);
  const [tab, setTab] = useState<"swap" | "liquidity">("swap");
  const owner = connected && account ? account.address.toString() : undefined;
  const wrongNetwork = connected && network && network.name.toLowerCase() !== cfg.networkName;

  return (
    <main className="shell">
      <header className="row between">
        <h1>Aegis</h1>
        {owner ? (
          <button onClick={() => disconnect()}>{short(owner)} · Disconnect</button>
        ) : (
          <div className="row">{wallets.length === 0 ? <span className="muted small">No Aptos wallet detected</span> : wallets.map((w) => <button key={w.name} onClick={() => connect(w.name)}>{w.name}</button>)}</div>
        )}
      </header>
      {cfg.networkName === "testnet" && <p className="banner">Testnet — tokens have no value.</p>}
      {wrongNetwork && <p className="banner error">Your wallet is on {network?.name}. Switch to {cfg.networkName}.</p>}
      <nav className="row small">
        <button className={tab === "swap" ? "chip active" : "chip"} onClick={() => setTab("swap")}>Swap</button>
        <button className={tab === "liquidity" ? "chip active" : "chip"} onClick={() => setTab("liquidity")}>Liquidity</button>
      </nav>
      {tab === "swap" ? <SwapCard cfg={cfg} aptos={aptos} client={client} owner={owner} /> : <LiquidityCard cfg={cfg} aptos={aptos} client={client} owner={owner} />}
      <footer className="muted small">
        Unaudited software. Only allowlisted tokens are shown; verify token addresses before trading. Swaps charge a 0.30 % fee paid to liquidity providers.
      </footer>
    </main>
  );
}
