import { useState } from "react";
import { auth, setToken, ApiError } from "../api";

type Mode = "login" | "register";

export function LoginPage({ onAuthed }: { onAuthed: () => void }) {
  const [mode, setMode] = useState<Mode>("login");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [orgName, setOrgName] = useState("");
  const [orgSlug, setOrgSlug] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const res =
        mode === "login"
          ? await auth.login(email, password)
          : await auth.register({ org_name: orgName, org_slug: orgSlug, email, password });
      setToken(res.access_token);
      onAuthed();
    } catch (err) {
      setError(err instanceof ApiError ? `${err.status}: ${err.message}` : "Request failed");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={submit}>
        <div className="brand-lg">Workflow&nbsp;Engine</div>
        <div className="seg">
          <button
            type="button"
            className={mode === "login" ? "seg-on" : ""}
            onClick={() => setMode("login")}
          >
            Sign in
          </button>
          <button
            type="button"
            className={mode === "register" ? "seg-on" : ""}
            onClick={() => setMode("register")}
          >
            Create org
          </button>
        </div>

        {mode === "register" ? (
          <>
            <label>
              Organization name
              <input value={orgName} onChange={(e) => setOrgName(e.target.value)} required />
            </label>
            <label>
              Organization slug
              <input
                value={orgSlug}
                onChange={(e) => setOrgSlug(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, "-"))}
                placeholder="acme"
                required
              />
            </label>
          </>
        ) : null}

        <label>
          Email
          <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Password
          <input
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>

        {error ? <div className="error pad">{error}</div> : null}

        <button className="primary" type="submit" disabled={busy}>
          {busy ? "…" : mode === "login" ? "Sign in" : "Create organization"}
        </button>
      </form>
    </div>
  );
}
