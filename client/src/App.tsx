import { Routes, Route } from "react-router-dom";
import { Layout } from "./components/Layout";
import { ValidatorDashboard } from "./pages/ValidatorDashboard";
import { SnapshotManager } from "./pages/SnapshotManager";
import { CreateSnapshot } from "./pages/CreateSnapshot";
import { ViewSnapshots } from "./pages/ViewSnapshots";
import { ERC20BalanceValidatorPage } from "./pages/ERC20BalanceValidatorPage";
import { GovernanceValidatorPage } from "./pages/GovernanceValidatorPage";
import { OpusTrovesValidatorPage } from "./pages/OpusTrovesValidatorPage";
import { TournamentValidatorPage } from "./pages/TournamentValidatorPage";
import { ZkPassportValidatorPage } from "./pages/ZkPassportValidatorPage";
import { MerkleValidatorPage } from "./pages/MerkleValidatorPage";
import { CreateMerkleTree } from "./pages/CreateMerkleTree";
import { MerkleProofLookup } from "./pages/MerkleProofLookup";

function App() {
  return (
    <Routes>
      <Route path="/" element={<Layout />}>
        <Route index element={<ValidatorDashboard />} />
        <Route path="snapshot" element={<SnapshotManager />} />
        <Route path="snapshot/create" element={<CreateSnapshot />} />
        <Route path="snapshot/view" element={<ViewSnapshots />} />
        <Route path="snapshot/view/:id" element={<ViewSnapshots />} />
        <Route path="erc20-balance" element={<ERC20BalanceValidatorPage />} />
        <Route path="governance" element={<GovernanceValidatorPage />} />
        <Route path="opus-troves" element={<OpusTrovesValidatorPage />} />
        <Route path="tournament" element={<TournamentValidatorPage />} />
        <Route path="zk-passport" element={<ZkPassportValidatorPage />} />
        <Route path="merkle" element={<MerkleValidatorPage />} />
        <Route path="merkle/create" element={<CreateMerkleTree />} />
        <Route path="merkle/proof" element={<MerkleProofLookup />} />
      </Route>
    </Routes>
  );
}

export default App;
