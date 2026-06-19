import React, { useEffect } from 'react';

export default function Modal({ title, children, buttons, onClose }) {
  useEffect(() => {
    const h = e => {
      if (e.key === 'Escape') {
        e.stopImmediatePropagation();
        onClose();
      }
    };
    document.addEventListener('keydown', h, true);
    return () => document.removeEventListener('keydown', h, true);
  }, [onClose]);

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal-panel" onClick={e => e.stopPropagation()}>
        <div className="modal-title">{title}</div>
        <div className="modal-body">{children}</div>
        <div className="modal-foot">
          {(buttons || [{ label: 'Close', fn: onClose }]).map((b, i) => (
            <button key={i} className={b.cls || ''} onClick={b.fn} disabled={b.disabled}>{b.label}</button>
          ))}
        </div>
      </div>
    </div>
  );
}
