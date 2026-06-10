export type RuleSeverity = 'error' | 'warning' | 'info'

export const rules: ReadonlyArray<readonly [string, RuleSeverity]> = [
  ['ci-command-drift', 'error'],
  ['console-log', 'warning'],
  ['debugger', 'error'],
  ['dockerignore-missing', 'warning'],
  ['duplicate-lockfiles', 'warning'],
  ['env-drift', 'error'],
  ['focused-test', 'error'],
  ['generated-files', 'warning'],
  ['merge-conflict', 'error'],
  ['package-lock-drift', 'warning'],
  ['readme-command-drift', 'warning'],
  ['skipped-test', 'error'],
  ['ts-ignore', 'warning'],
]
