import { Routes, Route } from "react-router-dom";
import { Layout } from "./components/Layout";
import { SnapshotManager } from "./pages/SnapshotManager";
import { CreateSnapshot } from "./pages/CreateSnapshot";
import { ViewSnapshots } from "./pages/ViewSnapshots";

function App() {
  return (
    <Routes>
      <Route path="/" element={<Layout />}>
        <Route index element={<SnapshotManager />} />
        <Route path="create" element={<CreateSnapshot />} />
        <Route path="snapshots" element={<ViewSnapshots />} />
        <Route path="snapshots/:id" element={<ViewSnapshots />} />
      </Route>
    </Routes>
  );
}

export default App;
