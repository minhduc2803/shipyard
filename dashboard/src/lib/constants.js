export const NODES = [
  ['intake', '\u{1F4DD}', 43], ['plan', '\u{1F9ED}', 129], ['implement', '\u{1F6E0}️', 215], ['gates', '\u{1F9EA}', 301],
  ['e2e·f', '\u{1F3AD}', 387], ['integrate', '\u{1F9E9}', 473], ['dev-gates', '\u{1F9EA}', 559], ['e2e', '\u{1F52C}', 645],
  ['review', '\u{1F440}', 731], ['QC', '\u{1F50D}', 817], ['sr gate', '\u{1F6A6}', 903], ['push dev', '\u{1F680}', 989],
  ['PR', '\u{1F500}', 1075], ['dev QC', '\u{1F310}', 1163], ['watch PR', '\u{1F501}', 1249], ['done', '✅', 1335],
];

export const MAINY = 66;
export const BUS = 196;
export const BLKY = 146;
export const FIXN = ['fix on branch', '\u{1F527}', 301, BUS];
export const BLKN = ['', '⛔', 951, BLKY];
export const TKT = ['ticket', '\u{1F3AB}', 1033, 20];

export const PHASES = [
  ['assigned', 'intake', 'claimed', 'bootstrapping'], ['plan'], ['implementing'],
  ['pre-push-gate'],
  ['e2e-feature', 'e2e-feature-passed'],
  ['integrated-testing', 'integrate-conflict', 'booting', 'live'], ['dev-gate'], ['e2e', 'e2e-passed'],
  ['review'], ['qc-plan', 'qc'],
  ['gate', 'gate-blocked'], ['pushing-development', 'pushed-development', 'push-conflict'],
  ['pr-open'], ['qc-dev', 'ticketed'], ['reported', 'watching-pr'], ['done'],
];

export function phaseIdx(stage) {
  return PHASES.findIndex(p => p.includes(stage));
}

export const ACT_CONFIRM = {
  up:     { m: "Boot / rebuild this lane's stack.", y: 'Boot' },
  down:   { m: "Stop this lane's stack (kills its servers, frees its ports).", y: 'Stop' },
  clear:  { m: 'Reset the status fields only (the "done with this feature" tidy-up). Does not touch code or the DB.', y: 'Clear' },
  reset:  { m: "Clean development + fresh DB — this wipes the lane's feature work.", y: 'Reset', cls: 'warn' },
  remove: { m: 'Deletes the clone, its databases, and state — no undo.', y: 'Remove', cls: 'warn' },
};
