# Tracker provider notes — <your provider>

Read at runtime by the ticketer agent. Only needed if your tracker's login isn't
a plain email+password form, or its issue search has quirks. Cover:
- **Login** — any multi-step form, SSO, or session lifetime the agent should know.
- **Idempotency search** — how to find an existing issue by title before creating.

Leave empty if your tracker is straightforward. Worked example:
`profiles/clinical/tracker-notes.md`.
