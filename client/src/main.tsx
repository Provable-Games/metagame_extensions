import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter } from "react-router-dom";
import { StarknetProvider } from "./contexts/StarknetProvider";
import { NetworkProvider } from "./contexts/NetworkContext";
import App from "./App";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <StarknetProvider>
      <NetworkProvider>
        <BrowserRouter>
          <App />
        </BrowserRouter>
      </NetworkProvider>
    </StarknetProvider>
  </StrictMode>,
);
