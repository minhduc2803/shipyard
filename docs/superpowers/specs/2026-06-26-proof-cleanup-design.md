# Proof screenshot cleanup — design

Date: 2026-06-26

## Problem

The watch dashboard renders each lane's QC proof screenshots
(`lanes/laneN/.playwright-mcp/proof/<feature-slug>/<group>/*.png`) read-only.
Over time a lane accumulates blurry/duplicate/obsolete screenshots and there is
no way to clean them up from the dashboard — the only recourse is manual `rm` in
the filesystem. We want an in-dashboard way to clean up a feature's screenshots
at three granularities: individual shots, a whole group, or all of a feature's
screenshots.

## Scope

In scope: deleting **screenshots only** (the `.png/.jpg/.jpeg` image files and
the per-group image dirs).

Explicitly out of scope (YAGNI):
- No trash/undo (deletes are permanent — confirmed once via a modal).
- No deletion of the `state/laneN/<slug>.json` record (the feature still shows
  in the picker after its screenshots are cleared).
- No deletion of the ticket report (`proof/<slug>/ticket/REPORT.html`).
- No bulk delete across multiple features.
- No new auth — relies on the existing localhost origin guard.

## Granularity (all three supported)

| User action            | Effect                                                        |
|------------------------|--------------------------------------------------------------|
| Delete individual shots| Unlink the selected image files within one group.            |
| Delete a group         | Remove a whole group dir (e.g. `qc-local/`) within a feature.|
| Clear all screenshots  | Remove every image **group** dir under a feature; keep `ticket/` and the state record. |

## Backend

### `services/proof.js` — `deleteProof(n, { slug, group, images })`

New function next to `proofPayload` / `proofFile`. Reuses the realpath
containment pattern from `proofFile`:

- Resolve `base = fs.realpathSync(proofBase(n))`. If it doesn't exist → throw.
- The feature root is `base/<slug>`; it must realpath-resolve to a path inside
  `base` and be a directory.
- The `ticket` group is never deletable (guard by name before resolving).
- Dispatch by body shape:
  - `images` present (non-empty array) **and** `group` present → for each image
    name, resolve `base/<slug>/<group>/<image>`, verify it is contained in
    `base`, is a real file, and matches `\.(png|jpg|jpeg)$`; unlink it. After
    unlinking, if the group dir is now empty, remove it.
  - `group` present, no `images` → resolve `base/<slug>/<group>`, verify
    contained + is a directory + name !== `ticket`; `rm -rf` it.
  - only `slug` → enumerate the feature dir's entries; for each subdir that is
    not `ticket`, `rm -rf` it. (Leaves `ticket/` and any non-dir files.)
- Reject any image name / group name containing a path separator or `..` before
  resolving (defense in depth on top of the realpath containment check).
- Returns `{ ok: true, deleted: <number of files removed> }`.

Directory removal uses `fs.rmSync(p, { recursive: true, force: true })`; count
files removed for the response.

### `routes/proof.js` — `DELETE /api/proof/:n(\\d)`

Reads `req.body` (express.json already mounted), calls `deleteProof`, returns
its result. On error → `500 { ok:false, error }`. The existing origin-guard
middleware already restricts to localhost.

## Frontend

### `lib/api.js`

Add `deleteProof(n, body)` performing `fetch(`/api/proof/${n}`, { method:'DELETE',
headers, body: JSON.stringify(body) })` through the existing `checked` helper.

### `ProofGallery.jsx` — cleanup mode (Option A)

Default view is unchanged. Add a `🧹 Clean up` toggle button to the feature
header (`pf-feat` head row).

When cleanup mode is **on**:
- Each thumbnail renders a checkbox overlay; clicking a thumbnail toggles its
  selection instead of opening the lightbox (`onShot`).
- Each group header (`pf-g`) gets a `🗑` button → confirm-delete that whole group.
- The feature header gets a **Clear all screenshots** button → confirm-delete all
  groups for the feature.
- A sticky mini-toolbar shows **Delete N selected** when ≥1 shot is selected,
  plus a **Clear selection** affordance.

Selection state (`Set` of `"group/image"` keys) and the cleanup-mode flag are
managed in `App.jsx` and passed down, OR kept local to `ProofGallery` with a
`useState`; they reset when the toggle flips off or the selected feature changes.
The `+N` overflow path and `GalleryModal` remain view-only in this iteration
(group-level delete covers large groups).

### Confirmation

`ConfirmModal` currently looks up copy from `ACT_CONFIRM[action]`. Extend it to
accept optional `{ title, message, confirmLabel, confirmCls }` props; when
provided they override the `ACT_CONFIRM` lookup. Cleanup flows pass a destructive
(red) confirm with a message naming the count, e.g.
*"Permanently delete 4 screenshots from qc-local? This cannot be undone."*

After a confirmed delete: call `loadProof(n, true)` to force-refresh, and clear
any selection.

## Data flow

1. User opens a lane's gallery, toggles **🧹 Clean up**.
2. User selects shots / clicks a group 🗑 / clicks **Clear all screenshots**.
3. `ConfirmModal` shows the count + destructive confirm.
4. On confirm → `deleteProof(n, body)` → server `deleteProof` unlinks within the
   realpath-guarded proof base.
5. App force-refreshes proof; gallery reflects the removed shots/groups.

## Error handling

- Server rejects path traversal and out-of-base paths (realpath containment),
  refuses the `ticket` group, and 500s with a message on any fs error.
- Client surfaces failures by simply re-loading proof (a failed delete leaves the
  files; the gallery is the source of truth). No optimistic removal.

## Testing

Server unit tests (dashboard `test/`):
- deletes named image files within a group and returns the right count;
- removes a whole group dir;
- clears all groups for a feature while leaving `ticket/` and the state JSON;
- prunes a group dir that becomes empty after file deletes;
- rejects path traversal (`../`, absolute paths) and refuses the `ticket` group;
- throws when the proof base / feature dir does not exist.

Manual: toggle cleanup mode in the running dashboard, delete a shot / group /
all, confirm the gallery updates and state/ticket are untouched.
