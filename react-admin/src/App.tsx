import { useState } from "react";
import { WorkflowsPage } from "./pages/WorkflowsPage";
import { ExecutionsPage } from "./pages/ExecutionsPage";
import { NodeTypesPage } from "./pages/NodeTypesPage";

type Tab = "workflows" | "executions" | "nodes";

const TABS: { id: Tab; label: string }[] = [
  { id: "workflows", label: "Workflows" },
  { id: "executions", label: "Executions" },
  { id: "nodes", label: "Node Types" },
];

export function App() {
  const [tab, setTab] = useState<Tab>("workflows");
  return (
    <div className="app">
      <header className="topbar">
        <div className="brand">Workflow&nbsp;Engine</div>
        <nav className="tabs">
          {TABS.map((t) => (
            <button
              key={t.id}
              className={tab === t.id ? "tab tab-active" : "tab"}
              onClick={() => setTab(t.id)}
            >
              {t.label}
            </button>
          ))}
        </nav>
      </header>
      <main className="content">
        {tab === "workflows" && <WorkflowsPage />}
        {tab === "executions" && <ExecutionsPage />}
        {tab === "nodes" && <NodeTypesPage />}
      </main>
    </div>
  );
}
