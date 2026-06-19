import React, { useState, useRef, useEffect } from 'react';
import Modal from './Modal.jsx';
import { postAction } from '../lib/api.js';

export default function AddLaneModal({ onClose, onDone }) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const focusRef = useRef(null);

  useEffect(() => {
    setTimeout(() => { if (focusRef.current) focusRef.current.focus(); }, 40);
  }, []);

  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async () => {
    setBusy(true);
    setError('');
    try {
      const body = (email.trim() || password) ? { email: email.trim(), password } : {};
      await postAction(null, 'add', body);
      onClose();
      onDone();
    } catch (e) {
      setError(e.message || 'Provisioning failed');
      setBusy(false);
    }
  };

  return (
    <Modal title="Provision a new lane" onClose={onClose}
      buttons={[
        { label: 'Cancel', fn: onClose, disabled: busy },
        { label: busy ? 'Provisioning…' : 'Provision lane', cls: 'add', fn: submit, disabled: busy },
      ]}>
      <p className="m-text">
        Sets up the next free lane: clone → deps → DB → MCPs → agents → sessions.
        It shows <b>{'⏳'} provisioning</b> with live progress and only turns ready when fully done.
      </p>
      <label className="m-l">dev-QC email <span style={{ color: 'var(--faint)' }}>(optional)</span>
        <input ref={focusRef} type="email" value={email} onChange={e => setEmail(e.target.value)}
          placeholder="qa account email" autoComplete="off" />
      </label>
      <label className="m-l">dev-QC password <span style={{ color: 'var(--faint)' }}>(optional)</span>
        <input type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete="off" />
      </label>
      <p className="m-hint">
        Set the dev-QC account now so it's embedded in the lane's agents — or leave blank and set it later with {'\u{1F511}'} creds.
      </p>
      {error && <p className="m-err">{error}</p>}
    </Modal>
  );
}
