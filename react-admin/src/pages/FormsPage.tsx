import { useEffect, useState } from "react";
import { api, ApiError } from "../api";
import type { FormDef, FormField, FormFieldType } from "../api";
import { useResource } from "../useResource";
import { Async } from "../ui";

const FIELD_TYPES: FormFieldType[] = [
  "text",
  "textarea",
  "number",
  "email",
  "date",
  "select",
  "checkbox",
];

export function FormsPage() {
  const list = useResource(() => api.forms(), []);
  // null = nothing selected; "new" = unsaved draft; else a form id.
  const [selected, setSelected] = useState<string | null>(null);

  return (
    <section className="split">
      <div className="split-list">
        <div className="detail-head">
          <h1>Forms</h1>
        </div>
        <p className="muted">Build forms that can trigger workflows.</p>
        <button className="primary block" onClick={() => setSelected("new")}>
          + New form
        </button>
        <Async state={list}>
          {(forms) =>
            forms.length === 0 ? (
              <div className="muted pad">No forms yet.</div>
            ) : (
              <ul className="rowlist">
                {forms.map((f) => (
                  <li
                    key={f.id}
                    className={selected === f.id ? "row row-sel" : "row"}
                    onClick={() => setSelected(f.id)}
                  >
                    <div className="row-main">
                      <span className="row-title">{f.name}</span>
                    </div>
                    <div className="muted small">{f.schema?.fields?.length ?? 0} fields</div>
                  </li>
                ))}
              </ul>
            )
          }
        </Async>
      </div>
      <div className="split-detail">
        {selected === null ? (
          <div className="muted pad">Select a form, or create one.</div>
        ) : (
          <FormEditor
            key={selected}
            formId={selected === "new" ? null : selected}
            onSaved={(id) => {
              list.reload();
              setSelected(id);
            }}
            onDeleted={() => {
              list.reload();
              setSelected(null);
            }}
          />
        )}
      </div>
    </section>
  );
}

function blankField(n: number): FormField {
  return { key: `field_${n}`, label: `Field ${n}`, type: "text", required: false, options: [] };
}

function FormEditor({
  formId,
  onSaved,
  onDeleted,
}: {
  formId: string | null;
  onSaved: (id: string) => void;
  onDeleted: () => void;
}) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [fields, setFields] = useState<FormField[]>([]);
  const [loading, setLoading] = useState(formId !== null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (formId === null) {
      setName("");
      setDescription("");
      setFields([]);
      setLoading(false);
      return;
    }
    let cancelled = false;
    setLoading(true);
    api
      .form(formId)
      .then((f: FormDef) => {
        if (cancelled) return;
        setName(f.name);
        setDescription(f.description ?? "");
        setFields(f.schema?.fields ?? []);
      })
      .catch((e) => setError(e instanceof ApiError ? `${e.status}: ${e.message}` : "Load failed"))
      .finally(() => !cancelled && setLoading(false));
    return () => {
      cancelled = true;
    };
  }, [formId]);

  function patch(i: number, p: Partial<FormField>) {
    setFields((fs) => fs.map((f, idx) => (idx === i ? { ...f, ...p } : f)));
  }
  function move(i: number, dir: -1 | 1) {
    setFields((fs) => {
      const j = i + dir;
      if (j < 0 || j >= fs.length) return fs;
      const copy = [...fs];
      [copy[i], copy[j]] = [copy[j], copy[i]];
      return copy;
    });
  }

  async function save() {
    setBusy(true);
    setError(null);
    try {
      const payload = { name, description, schema: { fields } };
      const saved =
        formId === null
          ? await api.createForm(payload)
          : await api.updateForm(formId, payload);
      onSaved(saved.id);
    } catch (e) {
      setError(e instanceof ApiError ? `${e.status}: ${e.message}` : "Save failed");
    } finally {
      setBusy(false);
    }
  }

  async function remove() {
    if (formId === null) return onDeleted();
    if (!confirm(`Delete form "${name}"?`)) return;
    setBusy(true);
    try {
      await api.deleteForm(formId);
      onDeleted();
    } catch (e) {
      setError(e instanceof ApiError ? `${e.status}: ${e.message}` : "Delete failed");
      setBusy(false);
    }
  }

  if (loading) return <div className="muted pad">Loading…</div>;

  return (
    <div>
      <div className="detail-head">
        <h2>{formId === null ? "New form" : "Edit form"}</h2>
        <div className="row-actions">
          <button className="primary" disabled={busy || !name} onClick={save}>
            {busy ? "Saving…" : "Save"}
          </button>
          <button className="danger" disabled={busy} onClick={remove}>
            {formId === null ? "Discard" : "Delete"}
          </button>
        </div>
      </div>
      {error ? <div className="error pad">{error}</div> : null}

      <div className="card">
        <label>
          Name
          <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Contact form" />
        </label>
        <label>
          Description
          <input value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>
      </div>

      <div className="card">
        <div className="detail-head">
          <h3>Fields ({fields.length})</h3>
          <button onClick={() => setFields((fs) => [...fs, blankField(fs.length + 1)])}>
            + Add field
          </button>
        </div>
        {fields.length === 0 ? (
          <p className="muted">No fields yet — add one.</p>
        ) : (
          <ul className="fieldlist">
            {fields.map((f, i) => (
              <li key={i} className="fieldrow">
                <div className="field-grid">
                  <label>
                    Key
                    <input value={f.key} onChange={(e) => patch(i, { key: e.target.value })} />
                  </label>
                  <label>
                    Label
                    <input value={f.label} onChange={(e) => patch(i, { label: e.target.value })} />
                  </label>
                  <label>
                    Type
                    <select
                      value={f.type}
                      onChange={(e) => patch(i, { type: e.target.value as FormFieldType })}
                    >
                      {FIELD_TYPES.map((t) => (
                        <option key={t} value={t}>
                          {t}
                        </option>
                      ))}
                    </select>
                  </label>
                  <label className="req">
                    <input
                      type="checkbox"
                      checked={f.required}
                      onChange={(e) => patch(i, { required: e.target.checked })}
                    />
                    Required
                  </label>
                </div>
                {f.type === "select" ? (
                  <label>
                    Options (comma-separated)
                    <input
                      value={f.options.join(", ")}
                      onChange={(e) =>
                        patch(i, {
                          options: e.target.value
                            .split(",")
                            .map((s) => s.trim())
                            .filter(Boolean),
                        })
                      }
                    />
                  </label>
                ) : null}
                <div className="field-actions">
                  <button onClick={() => move(i, -1)} disabled={i === 0} title="Move up">
                    ↑
                  </button>
                  <button
                    onClick={() => move(i, 1)}
                    disabled={i === fields.length - 1}
                    title="Move down"
                  >
                    ↓
                  </button>
                  <button
                    className="danger"
                    onClick={() => setFields((fs) => fs.filter((_, idx) => idx !== i))}
                  >
                    Remove
                  </button>
                </div>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="card">
        <h3>Preview</h3>
        <FormPreview name={name} fields={fields} />
      </div>
    </div>
  );
}

function FormPreview({ name, fields }: { name: string; fields: FormField[] }) {
  if (fields.length === 0) return <p className="muted">Add fields to see a preview.</p>;
  return (
    <form className="preview" onSubmit={(e) => e.preventDefault()}>
      {name ? <h4>{name}</h4> : null}
      {fields.map((f, i) => (
        <label key={i}>
          {f.label}
          {f.required ? <span className="req-star"> *</span> : null}
          {f.type === "textarea" ? (
            <textarea placeholder={f.placeholder ?? ""} rows={3} />
          ) : f.type === "select" ? (
            <select>
              <option value="">Select…</option>
              {f.options.map((o) => (
                <option key={o} value={o}>
                  {o}
                </option>
              ))}
            </select>
          ) : f.type === "checkbox" ? (
            <input type="checkbox" />
          ) : (
            <input type={f.type === "number" ? "number" : f.type === "email" ? "email" : f.type === "date" ? "date" : "text"} placeholder={f.placeholder ?? ""} />
          )}
        </label>
      ))}
      <button className="primary" type="submit">
        Submit
      </button>
    </form>
  );
}
