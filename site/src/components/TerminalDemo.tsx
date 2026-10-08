import { useEffect, useState } from 'react'
import { Win } from './Win'
import {
  CURSOR_HIDE_MS,
  CURSOR_SHOW_MS,
  RESTART_PAUSE_MS,
  script,
} from '../lib/terminalScript'

/* The live scan window in the hero: the animated typewriter script inside the
   shared Win chrome, with a static summary strip pinned under the body. */
export function TerminalDemo() {
  const [visibleCount, setVisibleCount] = useState(0)
  const [cursorVisible, setCursorVisible] = useState(false)
  const [runId, setRunId] = useState(0)

  useEffect(() => {
    setVisibleCount(0)
    setCursorVisible(false)
    const timers: number[] = []
    script.forEach((line, index) => {
      timers.push(window.setTimeout(() => setVisibleCount(index + 1), line.delay))
    })
    timers.push(window.setTimeout(() => setCursorVisible(true), CURSOR_SHOW_MS))
    timers.push(window.setTimeout(() => setCursorVisible(false), CURSOR_HIDE_MS))
    const lastDelay = script[script.length - 1].delay
    timers.push(window.setTimeout(() => setRunId((id) => id + 1), lastDelay + RESTART_PAUSE_MS))
    return () => timers.forEach(clearTimeout)
  }, [runId])

  return (
    <Win title="~/my-project">
      <div className="min-h-[188px] overflow-x-auto px-[18px] py-4">
        {script.map((line, index) => (
          <div
            key={index}
            className={`whitespace-pre font-mono text-[12.5px] leading-[2.1] transition-opacity duration-[120ms] ${
              index < visibleCount ? 'opacity-100' : 'opacity-0'
            }`}
          >
            {line.segments.map((segment, s) => (
              <span key={s} className={segment.className}>
                {segment.text}
              </span>
            ))}
            {index === 0 && cursorVisible && (
              <span className="animate-blink text-faint">▊</span>
            )}
          </div>
        ))}
      </div>
      <div className="flex items-center justify-between border-t border-edge-muted px-[18px] py-3">
        <span className="font-mono text-[12px] text-muted">4 findings</span>
        <button
          type="button"
          onClick={() => setRunId((id) => id + 1)}
          className="font-mono text-[11px] text-faint transition-colors hover:text-muted"
        >
          ↺ replay
        </button>
      </div>
    </Win>
  )
}
