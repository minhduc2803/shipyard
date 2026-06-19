import React from 'react';
import Modal from './Modal.jsx';
import { ACT_CONFIRM } from '../lib/constants.js';

export default function ConfirmModal({ lane, action, onConfirm, onClose }) {
  if (!action) return null;
  const c = ACT_CONFIRM[action] || { m: 'Proceed?', y: 'OK' };
  return (
    <Modal title={`Lane ${lane}: ${(c.y || action).toLowerCase()}?`} onClose={onClose}
      buttons={[
        { label: 'Cancel', fn: onClose },
        { label: c.y || 'Confirm', cls: c.cls || '', fn: () => { onClose(); onConfirm(); } },
      ]}>
      <p className="m-text">{c.m}</p>
    </Modal>
  );
}
