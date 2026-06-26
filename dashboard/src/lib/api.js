async function checked(r) {
  if (!r.ok) throw new Error(`HTTP ${r.status}`);
  return r.json();
}

export async function fetchLanes() {
  return checked(await fetch('/api/lanes'));
}

export async function fetchProof(n) {
  return checked(await fetch(`/api/proof/${n}`));
}

export async function fetchReviews(n) {
  return checked(await fetch(`/api/reviews/${n}`));
}

export async function fetchCreds(n) {
  return checked(await fetch(`/api/lane/${n}/creds-current`));
}

export async function deleteProof(n, body) {
  return checked(await fetch(`/api/proof/${n}`, {
    method: 'DELETE',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body || {}),
  }));
}

export async function postAction(n, action, body) {
  const opts = { method: 'POST' };
  if (body) {
    opts.headers = { 'Content-Type': 'application/json' };
    opts.body = JSON.stringify(body);
  }
  const url = n == null ? '/api/lanes/add' : `/api/lane/${n}/${action}`;
  return checked(await fetch(url, opts));
}
