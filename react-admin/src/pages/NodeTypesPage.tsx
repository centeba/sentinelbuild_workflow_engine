import { api } from "../api";
import type { NodeTypeEntry } from "../api";
import { useResource } from "../useResource";
import { Async } from "../ui";

export function NodeTypesPage() {
  const reg = useResource(() => api.nodeRegistry(), []);

  return (
    <section>
      <h1>Node Types</h1>
      <p className="muted">The palette available to the workflow builder — built-ins plus pack contributions.</p>
      <Async state={reg}>
        {(r) => {
          const builtinByGroup = groupBy(r.built_in_node_types ?? [], (n) => n.group_key ?? "ungrouped");
          return (
            <>
              <div className="stat-row">
                <Stat label="Built-in types" value={r.built_in_node_types?.length ?? 0} />
                <Stat label="Pack triggers" value={r.pack_triggers?.length ?? 0} />
                <Stat label="Pack actions" value={r.pack_actions?.length ?? 0} />
                <Stat label="Groups" value={(r.built_in_groups?.length ?? 0) + (r.pack_groups?.length ?? 0)} />
              </div>

              <div className="card">
                <h3>Built-in node types</h3>
                {Object.keys(builtinByGroup).length === 0 ? (
                  <p className="muted">No built-in node types.</p>
                ) : (
                  Object.entries(builtinByGroup).map(([group, items]) => (
                    <div key={group} className="group">
                      <div className="group-title">{group}</div>
                      <div className="chips">
                        {items.map((n) => (
                          <span key={n.key} className="chip" title={n.key}>
                            {n.label ?? n.key}
                          </span>
                        ))}
                      </div>
                    </div>
                  ))
                )}
              </div>

              {(r.pack_triggers?.length ?? 0) + (r.pack_actions?.length ?? 0) > 0 ? (
                <div className="card">
                  <h3>Pack contributions</h3>
                  <PackList title="Triggers" items={r.pack_triggers ?? []} />
                  <PackList title="Actions" items={r.pack_actions ?? []} />
                </div>
              ) : null}
            </>
          );
        }}
      </Async>
    </section>
  );
}

function PackList({ title, items }: { title: string; items: NodeTypeEntry[] }) {
  if (items.length === 0) return null;
  return (
    <div className="group">
      <div className="group-title">{title}</div>
      <div className="chips">
        {items.map((n) => (
          <span key={`${n.pack_name}:${n.key}`} className="chip" title={`${n.pack_name} · ${n.key}`}>
            {n.label ?? n.key} <span className="muted">({n.pack_name})</span>
          </span>
        ))}
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: number | string }) {
  return (
    <div className="stat-card">
      <div className="stat-value">{value}</div>
      <div className="stat-label">{label}</div>
    </div>
  );
}

function groupBy<T>(arr: T[], key: (t: T) => string): Record<string, T[]> {
  const out: Record<string, T[]> = {};
  for (const item of arr) {
    const k = key(item);
    (out[k] ??= []).push(item);
  }
  return out;
}
