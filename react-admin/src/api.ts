// Typed client for the workflow-engine API (/api/v1).
//
// Base URL defaults to "/api/v1" (dev-proxied by Vite); override with
// VITE_API_BASE. A bearer token, if present, is read from
// localStorage["we_token"].

const BASE = (import.meta.env.VITE_API_BASE as string | undefined) ?? "/api/v1";

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

function authHeaders(): Record<string, string> {
  const h: Record<string, string> = {};
  try {
    const token = localStorage.getItem("we_token");
    if (token) h["Authorization"] = `Bearer ${token}`;
  } catch {
    /* localStorage unavailable */
  }
  return h;
}

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: { "Content-Type": "application/json", ...authHeaders() },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!res.ok) {
    let detail = res.statusText;
    try {
      const j = await res.json();
      detail = j.detail ?? JSON.stringify(j);
    } catch {
      /* non-JSON body */
    }
    throw new ApiError(res.status, detail);
  }
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

// ── Domain types (mirror the backend schemas) ───────────────────────────────

export interface WorkflowNode {
  id?: string;
  key?: string;
  type?: string;
  label?: string;
  [k: string]: unknown;
}

export interface WorkflowDefinition {
  nodes?: WorkflowNode[];
  edges?: Array<Record<string, unknown>>;
  [k: string]: unknown;
}

export interface Workflow {
  id: string;
  name: string;
  description: string | null;
  definition: WorkflowDefinition;
  is_active: boolean;
  trigger_type: string;
  trigger_config: Record<string, unknown>;
  created_at: string;
  updated_at: string;
}

export interface Execution {
  id: string;
  workflow_id?: string;
  workflow_name?: string | null;
  status: string;
  trigger_type: string;
  input_data?: Record<string, unknown>;
  output_data?: Record<string, unknown>;
  error_message?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
  created_at: string;
  approval_status?: string | null;
}

export interface NodeExecution {
  id: string;
  node_id: string;
  node_key?: string;
  status: string;
  output_data?: Record<string, unknown>;
  error_message?: string | null;
  started_at?: string | null;
  completed_at?: string | null;
}

export interface NodeTypeEntry {
  key: string;
  group_key?: string;
  kind?: string;
  label?: string;
  pack_name?: string;
  [k: string]: unknown;
}

export interface NodeRegistry {
  built_in_groups: Array<Record<string, unknown>>;
  built_in_node_types: NodeTypeEntry[];
  pack_groups: NodeTypeEntry[];
  pack_triggers: NodeTypeEntry[];
  pack_actions: NodeTypeEntry[];
}

// ── Endpoints ───────────────────────────────────────────────────────────────

export const api = {
  workflows: () => request<Workflow[]>("GET", "/workflows"),
  workflow: (id: string) => request<Workflow>("GET", `/workflows/${id}`),
  executeWorkflow: (id: string) =>
    request<{ execution_id?: string; [k: string]: unknown }>(
      "POST",
      `/workflows/${id}/execute`,
      {},
    ),
  workflowExecutions: (id: string) =>
    request<Execution[]>("GET", `/workflows/${id}/executions`),

  executions: () => request<Execution[]>("GET", "/executions"),
  execution: (id: string) => request<Execution>("GET", `/executions/${id}`),
  executionNodes: (id: string) =>
    request<NodeExecution[]>("GET", `/executions/${id}/nodes`),

  nodeRegistry: () => request<NodeRegistry>("GET", "/node-types/registry"),
};
