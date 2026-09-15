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

const TOKEN_KEY = "we_token";

export function getToken(): string | null {
  try {
    return localStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}
export function setToken(token: string): void {
  try {
    localStorage.setItem(TOKEN_KEY, token);
  } catch {
    /* ignore */
  }
}
export function clearToken(): void {
  try {
    localStorage.removeItem(TOKEN_KEY);
  } catch {
    /* ignore */
  }
}

function authHeaders(): Record<string, string> {
  const h: Record<string, string> = {};
  const token = getToken();
  if (token) h["Authorization"] = `Bearer ${token}`;
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

export interface TokenResponse {
  access_token: string;
  refresh_token: string;
  token_type: string;
}

export interface RegisterInput {
  org_name: string;
  org_slug: string;
  email: string;
  password: string;
}

export const auth = {
  login: (email: string, password: string) =>
    request<TokenResponse>("POST", "/auth/login", { email, password }),
  register: (data: RegisterInput) =>
    request<TokenResponse>("POST", "/auth/register", data),
};

export interface NewWorkflow {
  name: string;
  description?: string;
  trigger_type: string;
  definition?: WorkflowDefinition;
  trigger_config?: Record<string, unknown>;
}

export type FormFieldType =
  | "text"
  | "textarea"
  | "number"
  | "email"
  | "date"
  | "select"
  | "checkbox";

export interface FormField {
  key: string;
  label: string;
  type: FormFieldType;
  required: boolean;
  placeholder?: string | null;
  options: string[];
}

export interface FormSchema {
  fields: FormField[];
}

export interface FormDef {
  id: string;
  org_id: string;
  name: string;
  description: string | null;
  schema: FormSchema;
  is_active: boolean;
  created_at: string;
  updated_at: string;
}

export interface FormInput {
  name: string;
  description?: string | null;
  schema: FormSchema;
  is_active?: boolean;
}

// ── Integrations / connectors ────────────────────────────────────────────────

/** A connector type from the built-in catalogue (connectors.json). */
export interface ConnectorCatalogueEntry {
  type: string;
  name: string;
  description: string;
  icon: string;
  category: string;
}

/** A configured integration instance for the org. */
export interface Integration {
  id: string;
  org_id: string;
  connector_type: string;
  name: string;
  credential_id: string | null;
  config: Record<string, unknown>;
}

export interface NewIntegration {
  connector_type: string;
  name: string;
  credential_id?: string | null;
  config?: Record<string, unknown>;
}

/** A stored credential (secrets never returned). */
export interface Credential {
  id: string;
  org_id: string;
  name: string;
  type: string;
  created_at: string;
}

export const api = {
  workflows: () => request<Workflow[]>("GET", "/workflows"),
  workflow: (id: string) => request<Workflow>("GET", `/workflows/${id}`),
  createWorkflow: (data: NewWorkflow) =>
    request<Workflow>("POST", "/workflows", {
      definition: { nodes: [], edges: [] },
      trigger_config: {},
      ...data,
    }),
  deleteWorkflow: (id: string) => request<void>("DELETE", `/workflows/${id}`),
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

  forms: () => request<FormDef[]>("GET", "/forms"),
  form: (id: string) => request<FormDef>("GET", `/forms/${id}`),
  createForm: (data: FormInput) => request<FormDef>("POST", "/forms", data),
  updateForm: (id: string, data: Partial<FormInput>) =>
    request<FormDef>("PUT", `/forms/${id}`, data),
  deleteForm: (id: string) => request<void>("DELETE", `/forms/${id}`),

  connectorCatalogue: () =>
    request<ConnectorCatalogueEntry[]>("GET", "/integrations/catalogue"),
  integrations: () => request<Integration[]>("GET", "/integrations"),
  createIntegration: (data: NewIntegration) =>
    request<Integration>("POST", "/integrations", data),
  deleteIntegration: (id: string) =>
    request<void>("DELETE", `/integrations/${id}`),

  credentials: () => request<Credential[]>("GET", "/credentials"),
  // OAuth2 connect for google/microsoft; returns a consent URL to open.
  oauth2Start: (connector: string, name: string) =>
    request<{ auth_url: string }>(
      "GET",
      `/oauth2/start?connector=${encodeURIComponent(connector)}&name=${encodeURIComponent(name)}`,
    ),
};
