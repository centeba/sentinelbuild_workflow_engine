import { useState } from "react";
import { api } from "../api";
import type { Execution } from "../api";
import { useResource } from "../useResource";
import { Async, StatusPill } from "../ui";

export function ExecutionsPage() {
  const list = useResource(() => api.executions(), []);
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <section className="split">
      <div className="split-list">
        <h1>Executions</h1>
        <p className="muted">Every workflow run, newest first.</p>
        <button className="ghost" onClick={() => list.reload()}>
          ↻ Refresh
        </button>
        <Async state={list}>
          {(rows) =>
            rows.length === 0 ? (
              <div className="muted pad">No executions.</div>
            ) : (
              <ul className="rowlist">
                {rows.map((e) => (
                  <li
                    key={e.id}
                    className={selected === e.id ? "row row-sel" : "row"}
                    onClick={() => setSelected(e.id)}
                  >
                    <div className="row-main">
                      <span className="row-title">{e.workflow_name ?? e.workflow_id ?? e.id}</span>
                      <StatusPill status={e.status} />
                    </div>
                    <div className="muted small">
                      {e.trigger_type} ·{" "}
                      {e.started_at ? new Date(e.started_at).toLocaleString() : "not started"}
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
          <ExecutionDetail id={selected} />
        ) : (
          <div className="muted pad">Select an execution.</div>
        )}
      </div>
    </section>
  );
}

function ExecutionDetail({ id }: { id: string }) {
  const ex = useResource(() => api.execution(id), [id]);
  const nodes = useResource(() => api.executionNodes(id), [id]);

  return (
    <Async state={ex}>
      {(e: Execution) => (
        <div>
          <div className="detail-head">
            <h2>{e.workflow_name ?? "Execution"}</h2>
            <StatusPill status={e.status} />
          </div>

          <div className="kv">
            <div>
              <span className="k">Trigger</span>
              {e.trigger_type}
            </div>
            <div>
              <span className="k">Started</span>
              {e.started_at ? new Date(e.started_at).toLocaleString() : "—"}
            </div>
            <div>
              <span className="k">Completed</span>
              {e.completed_at ? new Date(e.completed_at).toLocaleString() : "—"}
            </div>
            {e.approval_status ? (
              <div>
                <span className="k">Approval</span>
                {e.approval_status}
              </div>
            ) : null}
          </div>

          {e.error_message ? (
            <div className="error pad">
              <strong>Error:</strong> {e.error_message}
            </div>
          ) : null}

          <div className="card">
            <h3>Node steps</h3>
            <Async state={nodes}>
              {(rows) =>
                rows.length === 0 ? (
                  <p className="muted">No per-node records.</p>
                ) : (
                  <table className="table">
                    <thead>
                      <tr>
                        <th>Status</th>
                        <th>Node</th>
                        <th>Duration</th>
                      </tr>
                    </thead>
                    <tbody>
                      {rows.map((n) => (
                        <tr key={n.id}>
                          <td>
                            <StatusPill status={n.status} />
                          </td>
                          <td>
                            <code>{n.node_key ?? n.node_id}</code>
                          </td>
                          <td className="muted">{duration(n.started_at, n.completed_at)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )
              }
            </Async>
          </div>

          <details className="card">
            <summary>Input / output</summary>
            <pre className="json">{JSON.stringify(e.input_data ?? {}, null, 2)}</pre>
            <pre className="json">{JSON.stringify(e.output_data ?? {}, null, 2)}</pre>
          </details>
        </div>
      )}
    </Async>
  );
}

function duration(start?: string | null, end?: string | null): string {
  if (!start || !end) return "—";
  const ms = new Date(end).getTime() - new Date(start).getTime();
  if (ms < 0) return "—";
  if (ms < 1000) return `${ms} ms`;
  return `${(ms / 1000).toFixed(1)} s`;
}
