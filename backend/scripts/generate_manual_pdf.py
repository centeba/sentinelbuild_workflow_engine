"""Generate the Mit Stack user manual PDF using Playwright / Chromium."""

from playwright.sync_api import sync_playwright

HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap');

  :root {
    --navy:   #0F2744;
    --orange: #EA580C;
    --stone:  #44403C;
    --light:  #FAFAF9;
    --border: #E7E5E4;
    --code-bg:#F5F5F4;
    --muted:  #78716C;
  }

  * { box-sizing: border-box; margin: 0; padding: 0; }

  body {
    font-family: 'Inter', 'Segoe UI', sans-serif;
    font-size: 10.5pt;
    line-height: 1.65;
    color: #1C1917;
    background: white;
    padding: 0;
  }

  /* ── Cover page ─────────────────────────────────────────────── */
  .cover {
    height: 100vh;
    background: var(--navy);
    display: flex;
    flex-direction: column;
    justify-content: center;
    padding: 72px;
    page-break-after: always;
  }
  .cover-badge {
    display: inline-block;
    background: var(--orange);
    color: white;
    font-size: 8pt;
    font-weight: 700;
    letter-spacing: 2px;
    text-transform: uppercase;
    padding: 4px 12px;
    border-radius: 4px;
    margin-bottom: 32px;
    width: fit-content;
  }
  .cover h1 {
    font-size: 36pt;
    font-weight: 700;
    color: white;
    line-height: 1.2;
    margin-bottom: 16px;
  }
  .cover h1 span { color: var(--orange); }
  .cover p {
    font-size: 13pt;
    color: rgba(255,255,255,0.7);
    max-width: 480px;
    line-height: 1.6;
  }
  .cover-footer {
    margin-top: auto;
    padding-top: 48px;
    border-top: 1px solid rgba(255,255,255,0.15);
    color: rgba(255,255,255,0.4);
    font-size: 9pt;
  }

  /* ── TOC ────────────────────────────────────────────────────── */
  .toc {
    padding: 56px 72px;
    page-break-after: always;
  }
  .toc-header {
    font-size: 9pt;
    font-weight: 700;
    letter-spacing: 2px;
    text-transform: uppercase;
    color: var(--orange);
    margin-bottom: 24px;
  }
  .toc h2 { font-size: 22pt; font-weight: 700; color: var(--navy); margin-bottom: 32px; }
  .toc-item {
    display: flex;
    align-items: baseline;
    gap: 8px;
    padding: 8px 0;
    border-bottom: 1px solid var(--border);
  }
  .toc-item:last-child { border-bottom: none; }
  .toc-num { color: var(--orange); font-weight: 700; font-size: 9pt; min-width: 24px; }
  .toc-title { font-weight: 500; color: var(--navy); font-size: 10.5pt; }
  .toc-sub { padding-left: 28px; }
  .toc-sub .toc-title { font-weight: 400; color: var(--stone); font-size: 10pt; }

  /* ── Main content ───────────────────────────────────────────── */
  .content { padding: 56px 72px; }

  /* Part headers */
  .part-header {
    background: var(--navy);
    color: white;
    padding: 40px 72px;
    margin: 0 -72px 40px -72px;
    page-break-before: always;
  }
  .part-header:first-of-type { page-break-before: avoid; }
  .part-tag {
    font-size: 8pt;
    font-weight: 700;
    letter-spacing: 2px;
    text-transform: uppercase;
    color: var(--orange);
    margin-bottom: 8px;
  }
  .part-header h2 { font-size: 22pt; font-weight: 700; }

  h3 {
    font-size: 14pt;
    font-weight: 700;
    color: var(--navy);
    margin: 32px 0 12px;
    padding-bottom: 8px;
    border-bottom: 2px solid var(--orange);
    display: flex;
    align-items: center;
    gap: 10px;
  }
  h3 .step-num {
    background: var(--orange);
    color: white;
    font-size: 9pt;
    font-weight: 700;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
  }

  h4 {
    font-size: 11pt;
    font-weight: 600;
    color: var(--navy);
    margin: 24px 0 8px;
  }

  p { margin-bottom: 10px; }

  /* Tables */
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 16px 0 20px;
    font-size: 9.5pt;
  }
  thead tr { background: var(--navy); }
  thead th {
    color: white;
    font-weight: 600;
    text-align: left;
    padding: 9px 12px;
    font-size: 9pt;
    letter-spacing: 0.3px;
  }
  tbody tr { border-bottom: 1px solid var(--border); }
  tbody tr:nth-child(even) { background: var(--light); }
  td { padding: 8px 12px; vertical-align: top; }
  td:first-child { font-weight: 500; color: var(--navy); }

  /* Code */
  code, .mono {
    font-family: 'JetBrains Mono', 'Consolas', monospace;
    font-size: 9pt;
    background: var(--code-bg);
    color: var(--navy);
    padding: 1px 5px;
    border-radius: 3px;
  }
  pre {
    background: #1C1917;
    color: #D6D3D1;
    font-family: 'JetBrains Mono', 'Consolas', monospace;
    font-size: 8.5pt;
    padding: 16px 20px;
    border-radius: 8px;
    margin: 12px 0 20px;
    overflow: hidden;
    line-height: 1.7;
    border-left: 3px solid var(--orange);
  }
  pre .kw  { color: #FB923C; }
  pre .str { color: #86EFAC; }
  pre .cmt { color: #78716C; }
  pre .key { color: #93C5FD; }

  /* Callout boxes */
  .callout {
    background: #FFF7ED;
    border-left: 4px solid var(--orange);
    padding: 12px 16px;
    border-radius: 0 6px 6px 0;
    margin: 16px 0;
    font-size: 9.5pt;
  }
  .callout strong { color: var(--orange); }

  .callout-info {
    background: #EFF6FF;
    border-left-color: #2563EB;
  }
  .callout-info strong { color: #1D4ED8; }

  /* Lists */
  ul, ol { padding-left: 22px; margin-bottom: 12px; }
  li { margin-bottom: 5px; }

  /* Checklist */
  .checklist { list-style: none; padding-left: 0; }
  .checklist li {
    padding: 7px 10px 7px 36px;
    position: relative;
    border-bottom: 1px solid var(--border);
  }
  .checklist li:last-child { border-bottom: none; }
  .checklist li::before {
    content: "☐";
    position: absolute;
    left: 10px;
    color: var(--orange);
    font-size: 13pt;
    line-height: 1;
    top: 7px;
  }

  /* Flow diagram */
  .flow {
    background: var(--light);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 20px 24px;
    margin: 16px 0;
    font-size: 9.5pt;
  }
  .flow-step {
    display: flex;
    align-items: flex-start;
    gap: 12px;
    padding: 8px 0;
  }
  .flow-step:not(:last-child) {
    border-bottom: 1px dashed var(--border);
  }
  .flow-dot {
    width: 28px;
    height: 28px;
    background: var(--navy);
    color: white;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 9pt;
    flex-shrink: 0;
    margin-top: 1px;
  }
  .flow-arrow {
    text-align: center;
    color: var(--orange);
    font-size: 14pt;
    line-height: 1;
    padding: 2px 0;
  }
  .flow-label { font-weight: 600; color: var(--navy); }
  .flow-desc  { color: var(--stone); font-size: 9pt; }

  /* Node pill */
  .node-pill {
    display: inline-block;
    background: var(--navy);
    color: white;
    font-size: 8pt;
    font-weight: 600;
    padding: 2px 8px;
    border-radius: 4px;
    margin: 1px;
  }
  .node-pill.orange { background: var(--orange); }

  /* Page break helpers */
  .page-break { page-break-before: always; }

  /* Footer (via @page margin) */
  @page {
    margin: 0;
    size: A4;
  }
  @page :not(:first) {
    margin: 14mm 0;
  }
</style>
</head>
<body>

<!-- ══════════════════════════════════════════════════════════
     COVER
═══════════════════════════════════════════════════════════ -->
<div class="cover">
  <div class="cover-badge">User Manual</div>
  <h1>Integrating Forms,<br>Workflows <span>&amp; Rules</span></h1>
  <p>A step-by-step guide to building form-driven automations on Mit Stack — from creating a public form to firing rules on every submission.</p>
  <div class="cover-footer">
    Mit Stack &nbsp;·&nbsp; Workflow Automation Platform &nbsp;·&nbsp; v1.0
  </div>
</div>

<!-- ══════════════════════════════════════════════════════════
     TABLE OF CONTENTS
═══════════════════════════════════════════════════════════ -->
<div class="toc">
  <div class="toc-header">Contents</div>
  <h2>What's Inside</h2>

  <div class="toc-item">
    <span class="toc-num">01</span>
    <span class="toc-title">Overview — How the Three Pieces Fit Together</span>
  </div>
  <div class="toc-item">
    <span class="toc-num">02</span>
    <span class="toc-title">Part 1 — Create a Form</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Open the Form Builder &amp; add fields</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Configure form settings</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Save and share the public URL</span>
  </div>
  <div class="toc-item">
    <span class="toc-num">03</span>
    <span class="toc-title">Part 2 — Connect a Workflow</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Option A: Auto-generate from the form builder</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Option B: Build manually with a Form Trigger node</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">The submission event payload</span>
  </div>
  <div class="toc-item">
    <span class="toc-num">04</span>
    <span class="toc-title">Part 3 — Create Rules That Fire on Submission</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Creating a rule &amp; setting the trigger event</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Building condition trees</span>
  </div>
  <div class="toc-item toc-sub">
    <span class="toc-num">·</span>
    <span class="toc-title">Configuring THEN / ELSE actions</span>
  </div>
  <div class="toc-item">
    <span class="toc-num">05</span>
    <span class="toc-title">Part 4 — End-to-End Execution Order</span>
  </div>
  <div class="toc-item">
    <span class="toc-num">06</span>
    <span class="toc-title">Part 5 — Viewing Results &amp; Audit Logs</span>
  </div>
  <div class="toc-item">
    <span class="toc-num">07</span>
    <span class="toc-title">Quick-Start Checklist</span>
  </div>
</div>

<!-- ══════════════════════════════════════════════════════════
     CONTENT
═══════════════════════════════════════════════════════════ -->
<div class="content">

<!-- ── Overview ─────────────────────────────────────────────── -->
<div class="part-header" style="page-break-before:avoid">
  <div class="part-tag">Overview</div>
  <h2>How the Three Pieces Fit Together</h2>
</div>

<p>Mit Stack connects three independent but complementary features to create powerful, form-driven automations:</p>

<div class="flow">
  <div class="flow-step">
    <div class="flow-dot">1</div>
    <div>
      <div class="flow-label">Form</div>
      <div class="flow-desc">A public-facing page that collects structured data from anyone — no login required. Field values become the event payload that drives everything else.</div>
    </div>
  </div>
  <div class="flow-step">
    <div class="flow-dot">2</div>
    <div>
      <div class="flow-label">Workflow</div>
      <div class="flow-desc">A node graph that runs automatically on every form submission. Each node can validate data, send emails, call APIs, query a database, run AI analysis, or branch on conditions.</div>
    </div>
  </div>
  <div class="flow-step">
    <div class="flow-dot">3</div>
    <div>
      <div class="flow-label">Rules</div>
      <div class="flow-desc">Event-driven logic that evaluates the submission data against conditions and fires actions — independently of any workflow. Rules run in priority order; multiple rules can fire on a single submission.</div>
    </div>
  </div>
</div>

<div class="callout-info callout">
  <strong>Note:</strong> Workflows and rules both fire on the same submission event, but they are independent. A form can have a workflow, rules, both, or neither.
</div>

<!-- ══════════════════════════════════════════════════════════
     PART 1 — FORM
═══════════════════════════════════════════════════════════ -->
<div class="part-header">
  <div class="part-tag">Part 1</div>
  <h2>Create a Form</h2>
</div>

<h3><span class="step-num">1</span>Open the Form Builder</h3>
<p>Navigate to <strong>Forms</strong> in the left sidebar, then click <strong>New Form</strong> in the top-right corner. The form builder opens with a blank canvas.</p>

<h3><span class="step-num">2</span>Add Fields</h3>
<p>Click <strong>Add Field</strong> or drag from the field palette. All available field types are listed below:</p>

<table>
  <thead><tr><th>Category</th><th>Field Types</th></tr></thead>
  <tbody>
    <tr><td>Basic</td><td>Text, Textarea, Number, Email, Phone, URL</td></tr>
    <tr><td>Date &amp; Time</td><td>Date, Time, Date &amp; Time</td></tr>
    <tr><td>Choice</td><td>Dropdown (Select), Radio group, Checkbox, Multi-checkbox</td></tr>
    <tr><td>Advanced</td><td>Rating (1–5 stars), File upload</td></tr>
    <tr><td>Layout</td><td>Section divider (visual separator)</td></tr>
  </tbody>
</table>

<p>For each field, configure these properties in the right-hand panel:</p>

<table>
  <thead><tr><th>Property</th><th>Purpose</th></tr></thead>
  <tbody>
    <tr><td>Label</td><td>The question shown to the user</td></tr>
    <tr><td>Placeholder</td><td>Hint text shown inside the input before typing</td></tr>
    <tr><td>Required</td><td>Marks the field mandatory — enforced before submission</td></tr>
    <tr><td>Help text</td><td>Optional explanatory note displayed beneath the field</td></tr>
  </tbody>
</table>

<div class="callout">
  <strong>Tip:</strong> Give fields meaningful labels now. The auto-generated <strong>Field ID</strong> (shown in the properties panel) is what you reference in workflow nodes and rule conditions — e.g. <code>data.company_name</code>.
</div>

<h3><span class="step-num">3</span>Configure Form Settings</h3>
<p>Click the <strong>Settings</strong> (gear) icon on the toolbar to open the form configuration dialog:</p>

<table>
  <thead><tr><th>Setting</th><th>Purpose</th></tr></thead>
  <tbody>
    <tr><td>Form name</td><td>Internal label shown in the forms list</td></tr>
    <tr><td>URL slug</td><td>Public address: <code>your-domain/f/&lt;slug&gt;</code> — auto-generated but editable</td></tr>
    <tr><td>Public toggle</td><td>Must be <strong>ON</strong> for the form to accept submissions without login</td></tr>
    <tr><td>Submit button text</td><td>Defaults to "Submit" — customise as needed</td></tr>
    <tr><td>Success message</td><td>Text displayed to the user after a successful submission</td></tr>
    <tr><td>Redirect URL</td><td>Sends the user to another page after submission (optional)</td></tr>
    <tr><td>Webhook URL</td><td>Mit Stack will POST the submission JSON here on every submission (optional)</td></tr>
    <tr><td>Trigger workflow</td><td>Choose a workflow to run on every submission — see Part 2</td></tr>
  </tbody>
</table>

<h3><span class="step-num">4</span>Save and Share</h3>
<p>Click <strong>Save</strong>. The form is immediately live at its public URL. Share the slug link with your users — no account or login is required for them to fill it in.</p>

<!-- ══════════════════════════════════════════════════════════
     PART 2 — WORKFLOW
═══════════════════════════════════════════════════════════ -->
<div class="part-header">
  <div class="part-tag">Part 2</div>
  <h2>Connect a Workflow</h2>
</div>

<p>A workflow is a node graph that executes automatically every time your form is submitted. You can auto-generate one or build it manually.</p>

<h3>Option A — Auto-Generate (Recommended)</h3>
<p>In the Form Builder toolbar, click <strong>Generate Workflow</strong>. Mit Stack creates a complete workflow pre-wired to your form. The generated nodes depend on your form's configuration:</p>

<table>
  <thead><tr><th>Generated Node</th><th>What it does</th><th>When included</th></tr></thead>
  <tbody>
    <tr><td>Form Trigger</td><td>Listens for submissions of this specific form</td><td>Always</td></tr>
    <tr><td>Validate Required Fields</td><td>Checks all required fields are present; branches to error path if not</td><td>Always</td></tr>
    <tr><td>Store Submission</td><td>Saves the submission to the database</td><td>Always</td></tr>
    <tr><td>Format Response</td><td>Packages the output as a clean JSON object</td><td>Always</td></tr>
    <tr><td>Email Confirmation</td><td>Sends a confirmation email to the submitter</td><td>Form has an email field</td></tr>
    <tr><td>Webhook POST</td><td>Forwards data to your configured webhook URL</td><td>Webhook URL is set</td></tr>
    <tr><td>Mailchimp Subscribe</td><td>Adds the contact to a Mailchimp audience</td><td>Email field + subscribe checkbox detected</td></tr>
    <tr><td>LLM Analysis</td><td>Runs AI analysis on free-text response</td><td>Form has a textarea field</td></tr>
  </tbody>
</table>

<p>The generated workflow opens in the Workflow Builder. Customise any node, add new ones, then click <strong>Publish</strong>.</p>

<h3>Option B — Build Manually</h3>
<ol>
  <li>Go to <strong>Workflows → New Workflow</strong></li>
  <li>Set the trigger type to <strong>Form</strong></li>
  <li>Add a <span class="node-pill">Form Trigger</span> node and enter the form's <strong>slug</strong> in the node config</li>
  <li>Connect subsequent nodes — transforms, email senders, HTTP requests, AI nodes, etc.</li>
  <li>Click <strong>Publish</strong> when finished</li>
  <li>Back in <strong>Forms → Settings</strong>, select this workflow in the <em>Trigger workflow</em> dropdown</li>
</ol>

<h3>The Submission Event Payload</h3>
<p>When a user submits the form, Mit Stack passes this JSON structure into the workflow (and into the rules engine):</p>

<pre><span class="cmt">// Event payload — available in all workflow nodes and rule conditions</span>
{
  <span class="key">"form_id"</span>:       <span class="str">"uuid-of-the-form"</span>,
  <span class="key">"form_slug"</span>:     <span class="str">"your-slug"</span>,
  <span class="key">"submission_id"</span>: <span class="str">"uuid-of-this-submission"</span>,
  <span class="key">"data"</span>: {
    <span class="key">"field_id_1"</span>: <span class="str">"value the user typed"</span>,
    <span class="key">"field_id_2"</span>: <span class="str">"another value"</span>,
    <span class="cmt">// ... one key per form field</span>
  }
}</pre>

<p>In any node that accepts dynamic values, reference a submitted field with the path <code>data.&lt;field_id&gt;</code>. Find the field ID by clicking a field in the form builder and reading the <strong>Field ID</strong> in the properties panel.</p>

<!-- ══════════════════════════════════════════════════════════
     PART 3 — RULES
═══════════════════════════════════════════════════════════ -->
<div class="part-header">
  <div class="part-tag">Part 3</div>
  <h2>Create Rules That Fire on Submission</h2>
</div>

<p>Rules run on every form submission independently of any linked workflow. Every submission fires the rule engine with event type <code>form_submit</code>, and all published, active rules whose trigger events include <code>form_submit</code> are evaluated in priority order.</p>

<h3><span class="step-num">1</span>Create a New Rule</h3>
<p>Go to <strong>Rules → New Rule</strong>. Alternatively, click <strong>Generate with AI</strong> and describe what you want in plain English — the AI will draft the condition tree and actions for you.</p>

<h3><span class="step-num">2</span>Fill in Rule Info</h3>

<table>
  <thead><tr><th>Field</th><th>Notes</th></tr></thead>
  <tbody>
    <tr><td>Name</td><td>A clear, descriptive name — shown in audit logs</td></tr>
    <tr><td>Description</td><td>Optional. Useful for documenting the business reason</td></tr>
    <tr><td>Rule type</td><td><em>Condition Tree</em> covers most cases. <em>Decision Table</em> for matrix-style logic. <em>JavaScript</em> for custom code</td></tr>
    <tr><td>Priority</td><td>Lower number = evaluated first. Default 100. Use 10 for high-priority rules</td></tr>
    <tr><td>Stop on match</td><td>When ON, no lower-priority rules run after this one matches</td></tr>
  </tbody>
</table>

<h3><span class="step-num">3</span>Set the Trigger Event</h3>
<p>Under <strong>Trigger Events</strong>, select <code>form_submit</code>.</p>
<p>Optionally add a <strong>Trigger Filter</strong> — a fast pre-check applied before the full condition tree. For example, filter by <code>form_id = &lt;uuid&gt;</code> so the rule only fires for one specific form rather than every form in your organisation.</p>

<h3><span class="step-num">4</span>Build the Condition Tree</h3>
<p>Conditions reference the event payload using dot-notation paths:</p>

<table>
  <thead><tr><th>Path</th><th>What it accesses</th></tr></thead>
  <tbody>
    <tr><td><code>form_slug</code></td><td>The form's URL slug</td></tr>
    <tr><td><code>form_id</code></td><td>UUID of the form</td></tr>
    <tr><td><code>data.email_address</code></td><td>Value submitted in a field labelled "Email Address"</td></tr>
    <tr><td><code>data.company_name</code></td><td>Value in a "Company Name" field</td></tr>
    <tr><td><code>data.budget</code></td><td>Value in a numeric "Budget" field</td></tr>
  </tbody>
</table>

<p>All available condition operators:</p>

<table>
  <thead><tr><th>Type</th><th>Operators</th></tr></thead>
  <tbody>
    <tr><td>Text</td><td>equals, not equals, contains, not contains, starts with, ends with, matches regex</td></tr>
    <tr><td>Number</td><td>equals, greater than (&gt;), less than (&lt;), between</td></tr>
    <tr><td>List</td><td>in, not in</td></tr>
    <tr><td>Blank checks</td><td>is empty, is not empty</td></tr>
    <tr><td>Boolean</td><td>is true, is false</td></tr>
    <tr><td>Date</td><td>before, after, within last N days, older than N days</td></tr>
  </tbody>
</table>

<p>Groups of conditions can be combined with <strong>AND</strong> or <strong>OR</strong>, and groups can be nested. Example — fire if budget exceeds £10,000 <em>and</em> a company name was provided:</p>

<pre><span class="kw">AND</span>
  ├── <span class="key">data.budget</span>        <span class="str">greater than</span>   <span class="str">10000</span>
  └── <span class="key">data.company_name</span>  <span class="str">is not empty</span></pre>

<h3><span class="step-num">5</span>Configure THEN / ELSE Actions</h3>
<p><strong>THEN</strong> actions run when conditions match. <strong>ELSE</strong> actions run when they don't. Multiple actions can be chained — they execute in order.</p>

<table>
  <thead><tr><th>Action</th><th>What it does</th><th>Key fields</th></tr></thead>
  <tbody>
    <tr><td>Trigger workflow</td><td>Starts a workflow and passes the event data as input</td><td>Workflow to run</td></tr>
    <tr><td>Send email</td><td>Sends an email immediately</td><td>To, Subject, Body — supports <code>{{data.field_id}}</code> placeholders</td></tr>
    <tr><td>Send webhook</td><td>POSTs the event JSON to a URL</td><td>Webhook URL, optional extra headers</td></tr>
    <tr><td>Set field</td><td>Adds or overwrites a field in the event data (visible to downstream rules)</td><td>Field name, Value</td></tr>
    <tr><td>Add tag</td><td>Marks the submission with a label</td><td>Tag name</td></tr>
    <tr><td>Stop processing</td><td>Prevents any lower-priority rules from running after this one</td><td>—</td></tr>
  </tbody>
</table>

<h3><span class="step-num">6</span>Save and Publish</h3>
<ul>
  <li><strong>Save as Draft</strong> — rule is stored but not evaluated. Safe for work-in-progress rules.</li>
  <li><strong>Publish</strong> — rule becomes active immediately on the next form submission.</li>
</ul>
<p>To temporarily suspend a rule without deleting it, use the <strong>Active</strong> toggle in the rules list, or click <strong>Unpublish</strong>.</p>

<!-- ══════════════════════════════════════════════════════════
     PART 4 — EXECUTION ORDER
═══════════════════════════════════════════════════════════ -->
<div class="part-header">
  <div class="part-tag">Part 4</div>
  <h2>End-to-End Execution Order</h2>
</div>

<p>When a user submits a form, here is exactly what happens — in order:</p>

<div class="flow">
  <div class="flow-step">
    <div class="flow-dot">1</div>
    <div>
      <div class="flow-label">User submits the public form</div>
      <div class="flow-desc">Browser POSTs to <code>/public/forms/&lt;slug&gt;/submit</code> — no authentication required.</div>
    </div>
  </div>
  <div class="flow-step">
    <div class="flow-dot">2</div>
    <div>
      <div class="flow-label">Server-side validation</div>
      <div class="flow-desc">All required fields are checked. If any are missing, a 400 error is returned to the browser — no submission is saved.</div>
    </div>
  </div>
  <div class="flow-step">
    <div class="flow-dot">3</div>
    <div>
      <div class="flow-label">Submission saved</div>
      <div class="flow-desc">A <code>FormSubmission</code> record is written to the database with the full JSON payload and a unique submission ID.</div>
    </div>
  </div>
  <div class="flow-step">
    <div class="flow-dot">4</div>
    <div>
      <div class="flow-label">Linked workflow triggered (if configured)</div>
      <div class="flow-desc">If the form has a <em>Trigger workflow</em> set, a Temporal workflow execution starts asynchronously. The node graph runs in the background — validate → store → email → webhook → etc.</div>
    </div>
  </div>
  <div class="flow-step">
    <div class="flow-dot">5</div>
    <div>
      <div class="flow-label">Rule engine fires</div>
      <div class="flow-desc">All published + active rules with <code>form_submit</code> in their trigger events are loaded, sorted by priority, and evaluated in order. Each matching rule's THEN actions execute; non-matching rules run ELSE actions. All results are written to the audit log.</div>
    </div>
  </div>
  <div class="flow-step">
    <div class="flow-dot">6</div>
    <div>
      <div class="flow-label">Response returned to browser</div>
      <div class="flow-desc">The user sees the configured success message or is redirected to the configured URL.</div>
    </div>
  </div>
</div>

<div class="callout">
  <strong>Note on timing:</strong> The workflow (step 4) runs asynchronously via Temporal — it does not block the form response. Rules (step 5) run synchronously before the response is sent.
</div>

<!-- ══════════════════════════════════════════════════════════
     PART 5 — VIEWING RESULTS
═══════════════════════════════════════════════════════════ -->
<div class="part-header">
  <div class="part-tag">Part 5</div>
  <h2>Viewing Results &amp; Audit Logs</h2>
</div>

<h3>Workflow Executions</h3>
<p>Go to <strong>Executions</strong> in the sidebar. Each row shows the workflow that ran, its status (running / completed / failed), start time, and duration. Click any row to open the execution detail view — each node displays its exact input and output JSON, making it easy to debug unexpected behaviour.</p>

<h3>Rule Audit Log</h3>
<p>Go to <strong>Rules</strong>, open a rule, and click <strong>Audit Log</strong>. Each entry records:</p>
<ul>
  <li>Which event triggered the evaluation</li>
  <li>Whether the conditions matched (true / false)</li>
  <li>Which actions were executed and their results</li>
  <li>The full event payload that was evaluated</li>
  <li>Time elapsed</li>
</ul>

<h3>Form Submissions</h3>
<p>Go to <strong>Forms → [your form] → Submissions</strong>. Each submitted response is shown as a structured table. Click any row to view the raw JSON payload — the same data that was passed to the workflow and rule engine.</p>

<!-- ══════════════════════════════════════════════════════════
     QUICK-START CHECKLIST
═══════════════════════════════════════════════════════════ -->
<div class="part-header">
  <div class="part-tag">Quick-Start</div>
  <h2>Checklist</h2>
</div>

<p>Use this checklist to walk through the full integration from scratch:</p>

<ul class="checklist">
  <li>Go to <strong>Forms → New Form</strong> and add your fields</li>
  <li>Click the <strong>Settings</strong> gear — set the form name, slug, and toggle <strong>Public ON</strong></li>
  <li>Save the form and copy the public URL</li>
  <li>Click <strong>Generate Workflow</strong> (or create one manually with a Form Trigger node)</li>
  <li>Customise the generated workflow if needed, then click <strong>Publish</strong></li>
  <li>Back in <strong>Form Settings</strong> → select the workflow in <em>Trigger workflow</em></li>
  <li>Go to <strong>Rules → New Rule</strong> → set trigger event to <code>form_submit</code></li>
  <li>Add conditions referencing <code>data.&lt;field_id&gt;</code> values</li>
  <li>Add THEN actions (trigger workflow, send email, webhook, etc.)</li>
  <li>Click <strong>Publish</strong> on the rule</li>
  <li>Submit a test response via the public form URL</li>
  <li>Check <strong>Executions</strong> and the <strong>Rule Audit Log</strong> to confirm everything fired correctly</li>
</ul>

<br><br>
<div style="text-align:center; color:var(--muted); font-size:9pt; border-top:1px solid var(--border); padding-top:20px; margin-top:20px;">
  Mit Stack &nbsp;·&nbsp; Workflow Automation Platform &nbsp;·&nbsp; v1.0 &nbsp;·&nbsp; For internal use
</div>

</div><!-- /content -->
</body>
</html>
"""

OUTPUT = "/tmp/mit_stack_user_manual.pdf"

with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page()
    page.set_content(HTML, wait_until="networkidle")
    page.pdf(
        path=OUTPUT,
        format="A4",
        print_background=True,
        margin={"top": "0", "bottom": "0", "left": "0", "right": "0"},
    )
    browser.close()

print(f"PDF written to {OUTPUT}")
