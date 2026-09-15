import { useMemo, useState } from "react";
import { api, ApiError } from "../api";
import type { ConnectorCatalogueEntry, Credential, Integration } from "../api";
import { useResource } from "../useResource";
import { Async } from "../ui";

// Catalogue connector types that authenticate via the OAuth2 flow, mapped to the
// /oauth2/start `connector` value.
const OAUTH_CONNECTOR: Record<string, string> = {
  gmail: "google",
  outlook: "microsoft",
};

export function IntegrationsPage() {
  const catalogue = useResource(() => api.connectorCatalogue(), []);
  const configured = useResource(() => api.integrations(), []);
  const credentials = useResource(() => api.credentials(), []);
  const [actionError, setActionError] = useState<string | null>(null);

  const byType = useMemo(() => {
    const m = new Map<string, ConnectorCatalogueEntry>();
    for (const e of catalogue.data ?? []) m.set(e.type, e);
    return m;
  }, [catalogue.data]);

  function reloadAll() {
    configured.reload();
    credentials.reload();
  }

  async function remove(i: Integration) {
    if (!confirm(`Delete integration "${i.name}"?`)) return;
    setActionError(null);
    try {
      await api.deleteIntegration(i.id);
      configured.reload();
    } catch (e) {
      setActionError(e instanceof ApiError ? `${e.status}: ${e.message}` : "Delete failed");
    }
  }

  return (
    <section>
      <h1>Integrations</h1>
      <p className="muted">
        Connect the workflow engine to external services. Add a connector, then
        reference it from a workflow node.
      </p>
      {actionError ? <div className="error pad">{actionError}</div> : null}

      {/* ── Configured integrations ─────────────────────────────────────── */}
      <div className="card">
        <h3>Your integrations</h3>
        <Async state={configured}>
          {(items) =>
            items.length === 0 ? (
              <p className="muted">No integrations configured yet. Add one below.</p>
            ) : (
              <ul className="rowlist">
                {items.map((i) => {
                  const entry = byType.get(i.connector_type);
                  return (
                    <li key={i.id} className="row">
                      <div className="row-main">
                        <span className="row-title">
                          {entry?.icon ? `${entry.icon} ` : ""}
                          {i.name}
                        </span>
                        <div className="row-actions">
                          <span className="chip">{entry?.name ?? i.connector_type}</span>
                          {i.credential_id ? (
                            <span className="pill pill-ok">Credential linked</span>
                          ) : null}
                          <button className="danger" onClick={() => remove(i)}>
                            Delete
                          </button>
                        </div>
                      </div>
                    </li>
                  );
                })}
              </ul>
            )
          }
        </Async>
      </div>

      {/* ── Catalogue ───────────────────────────────────────────────────── */}
      <Async state={catalogue}>
        {(entries) => {
          const byCategory = groupByCategory(entries);
          return (
            <>
              {byCategory.map(([category, items]) => (
                <div key={category}>
                  <h2 className="group-title" style={{ marginTop: 22 }}>
                    {category}
                  </h2>
                  <div className="int-grid">
                    {items.map((e) => (
                      <ConnectorCard
                        key={e.type}
                        entry={e}
                        credentials={credentials.data ?? []}
                        onChanged={reloadAll}
                      />
                    ))}
                  </div>
                </div>
              ))}
            </>
          );
        }}
      </Async>
    </section>
  );
}

function groupByCategory(
  entries: ConnectorCatalogueEntry[],
): [string, ConnectorCatalogueEntry[]][] {
  const groups = new Map<string, ConnectorCatalogueEntry[]>();
  for (const e of entries) {
    const list = groups.get(e.category) ?? [];
    list.push(e);
    groups.set(e.category, list);
  }
  return [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]));
}

type KV = { key: string; value: string };

function ConnectorCard({
  entry,
  credentials,
  onChanged,
}: {
  entry: ConnectorCatalogueEntry;
  credentials: Credential[];
  onChanged: () => void;
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState(entry.name);
  const [credentialId, setCredentialId] = useState("");
  const [config, setConfig] = useState<KV[]>([{ key: "", value: "" }]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [oauthUrl, setOauthUrl] = useState<string | null>(null);

  const oauthConnector = OAUTH_CONNECTOR[entry.type];

  function setKV(i: number, patch: Partial<KV>) {
    setConfig((c) => c.map((row, idx) => (idx === i ? { ...row, ...patch } : row)));
  }

  async function save() {
    const cfg: Record<string, string> = {};
    for (const row of config) {
      if (row.key.trim()) cfg[row.key.trim()] = row.value;
    }
    setBusy(true);
    setError(null);
    try {
      await api.createIntegration({
        connector_type: entry.type,
        name: name.trim() || entry.name,
        credential_id: credentialId || null,
        config: cfg,
      });
      setOpen(false);
      setConfig([{ key: "", value: "" }]);
      onChanged();
    } catch (e) {
      setError(e instanceof ApiError ? `${e.status}: ${e.message}` : "Create failed");
    } finally {
      setBusy(false);
    }
  }

  async function startOauth() {
    setBusy(true);
    setError(null);
    setOauthUrl(null);
    try {
      const { auth_url } = await api.oauth2Start(oauthConnector, name.trim() || entry.name);
      setOauthUrl(auth_url);
    } catch (e) {
      setError(e instanceof ApiError ? `${e.status}: ${e.message}` : "Could not start OAuth");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="int-card">
      <div className="int-head">
        <span className="int-icon">{entry.icon || "🔌"}</span>
        <span className="int-name">{entry.name}</span>
      </div>
      <p className="int-desc">{entry.description}</p>
      <div className="row-actions">
        <button className="primary" onClick={() => setOpen((v) => !v)}>
          {open ? "Cancel" : "Add"}
        </button>
      </div>

      {error ? <div className="error pad small">{error}</div> : null}

      {open ? (
        <div className="int-add">
          <input
            placeholder="Name"
            value={name}
            onChange={(e) => setName(e.target.value)}
          />

          {credentials.length > 0 ? (
            <select value={credentialId} onChange={(e) => setCredentialId(e.target.value)}>
              <option value="">— No credential —</option>
              {credentials.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} ({c.type})
                </option>
              ))}
            </select>
          ) : null}

          {oauthConnector ? (
            <>
              <button className="ghost" disabled={busy} onClick={startOauth}>
                Authorize with OAuth ↗
              </button>
              {oauthUrl ? (
                <>
                  <span className="small muted">
                    Open this URL to grant access, then select the new credential above:
                  </span>
                  <div className="oauth-url">{oauthUrl}</div>
                  <a className="small" href={oauthUrl} target="_blank" rel="noreferrer">
                    Open consent screen ↗
                  </a>
                </>
              ) : null}
            </>
          ) : null}

          <span className="small muted">Config (optional)</span>
          {config.map((row, i) => (
            <div key={i} className="kvrow">
              <input
                placeholder="key"
                value={row.key}
                onChange={(e) => setKV(i, { key: e.target.value })}
              />
              <input
                placeholder="value"
                value={row.value}
                onChange={(e) => setKV(i, { value: e.target.value })}
              />
              <button
                className="danger"
                disabled={config.length === 1}
                onClick={() => setConfig((c) => c.filter((_, idx) => idx !== i))}
                title="Remove"
              >
                ✕
              </button>
            </div>
          ))}
          <div className="row-actions">
            <button onClick={() => setConfig((c) => [...c, { key: "", value: "" }])}>
              Add field
            </button>
            <button className="primary" disabled={busy} onClick={save}>
              {busy ? "Saving…" : "Save integration"}
            </button>
          </div>
        </div>
      ) : null}
    </div>
  );
}
