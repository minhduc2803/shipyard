import React, { useState, useEffect, useCallback } from 'react';
import { useLanes } from './hooks/useLanes.js';
import { useProof } from './hooks/useProof.js';
import { useReviews } from './hooks/useReviews.js';
import { postAction, deleteProof } from './lib/api.js';
import Header from './components/Header.jsx';
import LaneGrid from './components/LaneGrid.jsx';
import PipelineMap from './components/PipelineMap.jsx';
import ProofGallery from './components/ProofGallery.jsx';
import ReviewTable from './components/ReviewTable.jsx';
import Lightbox from './components/Lightbox.jsx';
import GalleryModal from './components/GalleryModal.jsx';
import ConfirmModal from './components/ConfirmModal.jsx';
import CredentialsModal from './components/CredentialsModal.jsx';
import AddLaneModal from './components/AddLaneModal.jsx';

export default function App() {
  const { data, refreshNow } = useLanes();
  const [selectedLane, setSelectedLane] = useState(null);
  const [shot, setShot] = useState(null);
  const [gallery, setGallery] = useState(null);
  const [confirm, setConfirm] = useState(null);
  const [credsModal, setCredsModal] = useState(null);
  const [addLane, setAddLane] = useState(false);

  const lanes = data?.lanes || [];
  const config = data?.config || {};

  // auto-select first running lane
  useEffect(() => {
    if (!lanes.length) return;
    if (selectedLane != null && lanes.some(l => l.lane === selectedLane)) return;
    const run = lanes.find(l => l.status === 'running');
    setSelectedLane((run || lanes[0]).lane);
  }, [lanes, selectedLane]);

  const selectedLaneData = lanes.find(l => l.lane === selectedLane);

  const { proof, loadProof, selectFeature, selectedSlug } = useProof(selectedLane, lanes);
  const { reviews, loadReviews } = useReviews(selectedLane, lanes);

  // Is the picker on a PAST feature (not the lane's current one)?
  const viewingPast = !!(proof && selectedSlug && proof._cur && selectedSlug !== proof._cur);
  const selectedFeature = viewingPast ? (proof.features || []).find(f => f.slug === selectedSlug) : null;
  const selectedFeatureState = selectedFeature?.state || null;

  // A read-only "proof only" snapshot for older features whose pipeline state was
  // never persisted (proof dirs exist, but no state/laneN/<slug>.json).
  const proofOnly = {
    lane: selectedLaneData?.lane, mode: selectedLaneData?.mode,
    feature_title: selectedSlug, stage: 'proof only', status: 'archived',
    gate_decision: '', pr_url: '', ticket_url: '', stalled: false, stage_age_sec: null,
    notes: 'Proof only — no pipeline state was recorded for this past feature.',
  };

  // Map + card follow the picker: live lane for the current feature; the archived
  // snapshot if we have one; otherwise the proof-only view. Always switches.
  const mapLane = !viewingPast
    ? selectedLaneData
    : selectedFeatureState
      ? { ...selectedLaneData, ...selectedFeatureState,
          feature_title: selectedFeatureState.feature_title || selectedSlug,
          stage_age_sec: null, stalled: false }
      : proofOnly;
  const cardFeatureState = !viewingPast ? null : (selectedFeatureState || proofOnly);

  // soft refresh proof/reviews on each data tick
  useEffect(() => {
    if (selectedLane == null || !selectedLaneData) return;
    if (selectedLaneData.mode === 'pr-review') {
      loadReviews(selectedLane, false);
    } else {
      loadProof(selectedLane, false);
    }
  }, [data, selectedLane]);

  // keyboard handling for gallery modal (Esc)
  useEffect(() => {
    const h = e => {
      if (shot && e.key === 'Escape') { /* Lightbox handles its own */ return; }
      if (gallery && e.key === 'Escape') setGallery(null);
    };
    document.addEventListener('keydown', h);
    return () => document.removeEventListener('keydown', h);
  }, [shot, gallery]);

  const handleAction = useCallback((n, action) => {
    setConfirm({ lane: n, action, onConfirm: async () => {
      try { await postAction(n, action); } catch {}
      refreshNow();
    }});
  }, [refreshNow]);

  const handleCreds = useCallback((n, mode) => {
    setCredsModal({ lane: n, mode });
  }, []);

  const handleCleanup = useCallback((n, payload, label, after) => {
    setConfirm({
      lane: n,
      title: 'Delete screenshots?',
      message: `Permanently delete ${label}? This cannot be undone.`,
      confirmLabel: 'Delete',
      confirmCls: 'warn',
      onConfirm: async () => {
        try {
          if (payload._multi) {
            for (const [group, images] of Object.entries(payload._multi))
              await deleteProof(n, { slug: payload.slug, group, images });
          } else {
            await deleteProof(n, payload);
          }
        } catch { /* gallery refresh below reflects truth */ }
        if (after) after();
        loadProof(n, true);
      },
    });
  }, [loadProof]);

  const openShot = useCallback((slug, g, ix) => {
    if (!proof) return;
    const f = proof.features.find(x => x.slug === slug);
    if (!f) return;
    setShot({ slug, g, imgs: f.groups[g] || [], i: ix, lane: proof.lane });
  }, [proof]);

  const shotNav = useCallback((d) => {
    setShot(prev => {
      if (!prev) return prev;
      const ni = prev.i + d;
      if (ni < 0 || ni >= prev.imgs.length) return prev;
      return { ...prev, i: ni };
    });
  }, []);

  const openGallery = useCallback((slug, g) => {
    if (!proof) return;
    const f = proof.features.find(x => x.slug === slug);
    if (!f) return;
    setGallery({ slug, g, imgs: f.groups[g] || [], lane: proof.lane });
  }, [proof]);

  return (
    <>
      <Header lanes={lanes} onAddLane={() => setAddLane(true)} />

      {selectedLaneData && (
        selectedLaneData.mode === 'pr-review' ? (
          <div className="mapwrap">
            <div className="maphead">
              <b>Lane {selectedLaneData.lane}</b>
              <span className="stagechip q">{selectedLaneData.stage}</span>
              <span style={{ color: 'var(--dim)' }}>{selectedLaneData.feature_title || '(idle)'}</span>
              <span className="hint">click a card to map another lane</span>
            </div>
            <ReviewTable reviews={reviews} needsAction={selectedLaneData.needs_action} config={config} />
          </div>
        ) : (
          <>
            <PipelineMap lane={mapLane} config={config} archived={viewingPast} />
            <div className="mapwrap" style={{ padding: '0 18px 6px', marginTop: '-12px', borderTop: 'none', boxShadow: 'none', background: 'transparent' }}>
              <ProofGallery proof={proof} selectedLane={selectedLane} selectedSlug={selectedSlug}
                onSelectFeature={selectFeature} onShot={openShot} onGallery={openGallery}
                onCleanup={handleCleanup} />
            </div>
          </>
        )
      )}

      <LaneGrid lanes={lanes} selectedLane={selectedLane} featureState={cardFeatureState}
        onSelect={n => setSelectedLane(n)} onAction={handleAction} onCreds={handleCreds} />

      {confirm && (
        <ConfirmModal lane={confirm.lane} action={confirm.action}
          title={confirm.title} message={confirm.message}
          confirmLabel={confirm.confirmLabel} confirmCls={confirm.confirmCls}
          onConfirm={confirm.onConfirm} onClose={() => setConfirm(null)} />
      )}
      {credsModal && (
        <CredentialsModal lane={credsModal.lane} mode={credsModal.mode} config={config}
          onClose={() => setCredsModal(null)} onDone={refreshNow} />
      )}
      {addLane && (
        <AddLaneModal onClose={() => setAddLane(false)} onDone={refreshNow} />
      )}
      <GalleryModal gallery={gallery} onClose={() => setGallery(null)} onShot={openShot} />
      <Lightbox shot={shot} onClose={() => setShot(null)} onNav={shotNav} />
    </>
  );
}
