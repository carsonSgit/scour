export interface Segment {
  text: string
  className: string
}

export interface ScriptLine {
  delay: number
  segments: Segment[]
}

export const CURSOR_SHOW_MS = 400
export const CURSOR_HIDE_MS = 1000
export const RESTART_PAUSE_MS = 4000

const rule = 'text-secondary'
const path = 'text-muted'

export const script: ScriptLine[] = [
  {
    delay: 0,
    segments: [
      { text: '❯ ', className: 'text-ok' },
      { text: 'scour --all', className: 'text-primary' },
    ],
  },
  {
    delay: 1000,
    segments: [
      { text: '✗  ', className: 'text-error' },
      { text: 'env-drift             ', className: rule },
      { text: '.env.example', className: path },
    ],
  },
  {
    delay: 1300,
    segments: [
      { text: '✗  ', className: 'text-error' },
      { text: 'debugger              ', className: rule },
      { text: 'src/api.ts:42', className: path },
    ],
  },
  {
    delay: 1600,
    segments: [
      { text: '⚠  ', className: 'text-warn' },
      { text: 'console-log           ', className: rule },
      { text: 'src/utils.ts:18', className: path },
    ],
  },
  {
    delay: 1900,
    segments: [
      { text: '⚠  ', className: 'text-warn' },
      { text: 'package-lock-drift    ', className: rule },
      { text: 'package.json', className: path },
    ],
  },
  {
    delay: 2200,
    segments: [{ text: '──────────────────────────────────────', className: 'text-faint' }],
  },
  {
    delay: 2400,
    segments: [{ text: '4 issues · 2 errors · 2 warnings', className: path }],
  },
]
