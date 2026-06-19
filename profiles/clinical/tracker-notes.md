# Tracker provider notes — eastagile (clinical)

Read at runtime by the **ticketer** agent for provider-specific login + search
guidance. These apply to the **East Agile** tracker; another provider writes its
own `tracker-notes.md` (or leaves it empty if its tracker uses a plain
email+password login).

- **Login (two-step form):** when typing the embedded credentials yourself, it's
  a two-step form — type the email → click Continue → type the password → click
  Continue. The login page title is "Log in". Sessions expire ~7 days.
- **Idempotency search:** use the project, status, and assignee from the injected
  **Tracker target:** line. Search that project by title before creating, to
  avoid duplicates.
