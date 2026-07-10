export type RuleSeverity = 'error' | 'warning' | 'info'

export const rules: ReadonlyArray<readonly [string, RuleSeverity]> = [
  ['ci-command-drift', 'error'],
  ['console-log', 'warning'],
  ['debugger', 'error'],
  ['dependency-lock-drift', 'warning'],
  ['dockerignore-missing', 'warning'],
  ['duplicate-lockfiles', 'warning'],
  ['env-drift', 'error'],
  ['focused-test', 'error'],
  ['generated-files', 'warning'],
  ['hardcoded-secret', 'error'],
  ['merge-conflict', 'error'],
  ['package-lock-drift', 'warning'],
  ['readme-command-drift', 'warning'],
  ['skipped-test', 'error'],
  ['tracked-env-file', 'error'],
  ['ts-ignore', 'warning'],
  ['unpinned-github-action', 'warning'],
]
