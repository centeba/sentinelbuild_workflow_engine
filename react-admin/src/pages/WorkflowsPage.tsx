import { useState } from "react";
import { api, ApiError } from "../api";
import type { Workflow } from "../api";
import { useResource } from "../useResource";
import { Async, ActiveBadge, StatusPill } from "../ui";

export function WorkflowsPage() {
  const list = useResource(() => api.workflows(), []);
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <section className="split">
      <div className="split-list">
        <h1>Workflows</h1>
        <p className="muted">Definitions and their triggers.</p>
        <Async state={list}>
          {(workflows) =>
            workflows.length === 0 ? (
              <div className="muted pad">No workflows defined.</div>
            ) : (
              <ul className="rowlist">
                {workflows.map((w) => (
                  <li
                    key={w.id}
                    className={selected === w.id ? "row row-sel" : "row"}
                    onClick={() => setSelected(w.id)}
                  >
                    <div className="row-main">
                      <span className="row-title">{w.name}</span>
                      <ActiveBadge active={w.is_active} />
                    </div>
                    <div className="muted small">
                      {w.trigger_type} · {(w.definition?.nodes?.length ?? 0)} nodes
                    </div>
                  </li>
                ))}
              </ul>
            )
          }
        </Async>
      </div>
      <div className="split-detail">
        {selected ? (
          <WorkflowDetail id={selected} onChanged={() => list.reload()} />
        ) : (
          <div className="muted pad">Select a workflow.</div>
        )}
      </div>
    </section>
  );
}

function WorkflowDetail({ id, onChanged }: { id: string; onChanged: () => void }) {
  const wf = useResource(() => api.workflow(id), [id]);
  const execs = useResource(() => api.workflowExecutions(id), [id]);
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  async function execute() {
    setBusy(true);
    setMsg(null);
    try {
      await api.executeWorkflow(id);
      setMsg("Execution triggered.");
      execs.reload();
      onChanged();
    } catch (e) {
      setMsg(e instanceof ApiError ? `${e.status}: ${e.message}` : "Trigger failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Async state={wf}>
      {(w: Workflow) => (
        <div>
          <div className="detail-head">
            <div>
              <h2>{w.name}</h2>
              {w.description ? <p className="muted">{w.description}</p> : null}
            </div>
            <button disabled={busy} onClick={execute}>
              {busy ? "Triggering…" : "Execute"}
            </button>
          </div>
          {msg ? <div className="note">{msg}</div> : null}

          <div className="kv">
            <div>
              <span className="k">Status</span>
              <ActiveBadge active={w.is_active} />
            </div>
            <div>
              <span className="k">Trigger</span>
              {w.trigger_type}
            </div>
            <div>
              <span className="k">Updated</span>
              {new Date(w.updated_at).toLocaleString()}
            </div>
          </div>

          <div className="card">
            <h3>Nodes ({w.definition?.nodes?.length ?? 0})</h3>
            {(w.definition?.nodes?.length ?? 0) === 0 ? (
              <p className="muted">No nodes in this definition.</p>
            ) : (
              <ul className="nodes">
                {w.definition!.nodes!.map((n, i) => (
                  <li key={n.id ?? n.key ?? i}>
                    <code>{String(n.type ?? n.key ?? "node")}</code>
                    <span className="muted"> {String(n.label ?? n.id ?? n.key ?? "")}</span>
                  </li>
                ))}
              </ul>
            )}
            <div className="muted small">{w.definition?.edges?.length ?? 0} edges</div>
          </div>

          <div className="card">
            <h3>Recent executions</h3>
            <Async state={execs}>
              {(rows) =>
                rows.length === 0 ? (
                  <p className="muted">No executions yet.</p>
                ) : (
                  <table className="table">
                    <thead>
                      <tr>
                        <th>Status</th>
                        <th>Trigger</th>
                        <th>Started</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.slice(0, 10).map((e) => (
                        <tr key={e.id}>
                          <td>
                            <StatusPill status={e.status} />
                          </td>
                          <td>{e.trigger_type}</td>
                          <td className="muted">
                            {e.started_at ? new Date(e.started_at).toLocaleString() : "—"}
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )
              }
            </Async>
          </div>
        </div>
      )}
    </Async>
  );
}
