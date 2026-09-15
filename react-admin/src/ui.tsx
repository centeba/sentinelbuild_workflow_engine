import type { ReactNode } from "react";
import type { AsyncState } from "./useResource";

/** Renders loading / error / empty / data states for an async resource. */
export function Async<T>({
  state,
  children,
  empty,
}: {
  state: AsyncState<T>;
  children: (data: T) => ReactNode;
  empty?: ReactNode;
}) {
  if (state.loading && state.data === null) return <div className="muted pad">Loading…</div>;
  if (state.error)
    return (
      <div className="error pad">
        <p>{state.error}</p>
        <button onClick={state.reload}>Retry</button>
      </div>
    );
  if (state.data === null) return <>{empty ?? <div className="muted pad">No data.</div>}</>;
  return <>{children(state.data)}</>;
}

/** Semantic status pill for execution / node states. */
export function StatusPill({ status }: { status: string }) {
  const s = (status || "").toLowerCase();
  const kind =
    ["succeeded", "completed", "success", "ok", "approved"].includes(s)
      ? "ok"
      : ["failed", "error", "cancelled", "canceled", "rejected", "timed_out"].includes(s)
        ? "bad"
        : ["running", "in_progress", "started"].includes(s)
          ? "run"
          : "warn";
  return <span className={`pill pill-${kind}`}>{status || "—"}</span>;
}

/** An on/off badge for a boolean like is_active. */
export function ActiveBadge({ active }: { active: boolean }) {
  return (
    <span className={`pill ${active ? "pill-ok" : "pill-idle"}`}>{active ? "Active" : "Inactive"}</span>
  );
}
