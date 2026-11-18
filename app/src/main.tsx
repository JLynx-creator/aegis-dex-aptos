import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { AptosWalletAdapterProvider } from "@aptos-labs/wallet-adapter-react";
import { loadConfig, type AppConfig } from "./config";
import { App } from "./App";
import "./styles.css";

function Root() {
  let cfg: AppConfig;
  try {
    cfg = loadConfig();
  } catch (e) {
    return (
      <main className="shell">
        <div className="card error">Configuration error: {(e as Error).message}</div>
      </main>
    );
  }
  return (
    <AptosWalletAdapterProvider autoConnect dappConfig={{ network: cfg.network }}>
      <App cfg={cfg} />
    </AptosWalletAdapterProvider>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <Root />
  </StrictMode>,
);
