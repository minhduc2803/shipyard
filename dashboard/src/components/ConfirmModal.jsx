import React from 'react';
import Modal from './Modal.jsx';
import { ACT_CONFIRM } from '../lib/constants.js';

// Backwards compatible: when `action` is given it looks up copy from ACT_CONFIRM.
// Callers may instead pass generic { title, message, confirmLabel, confirmCls }
// to override that copy (used by the proof-cleanup flows).
export default function ConfirmModal({
  lane, action, title, message, confirmLabel, confirmCls, onConfirm, onClose,
}) {
  if (!action && !message) return null;
  const c = ACT_CONFIRM[action] || { m: 'Proceed?', y: 'OK' };
  const yLabel = confirmLabel || c.y || 'Confirm';
  const ttl = title || `Lane ${lane}: ${yLabel.toLowerCase()}?`;
  const msg = message || c.m;
  const yCls = confirmCls || c.cls || '';
  return (
    <Modal title={ttl} onClose={onClose}
      buttons={[
        { label: 'Cancel', fn: onClose },
        { label: yLabel, cls: yCls, fn: () => { onClose(); onConfirm(); } },
      ]}>
      <p className="m-text">{msg}</p>
    </Modal>
  );
}
