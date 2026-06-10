import { useEffect, useState } from 'react'
import {
  CURSOR_HIDE_MS,
  CURSOR_SHOW_MS,
  RESTART_PAUSE_MS,
  script,
} from '../lib/terminalScript'

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
    <section className="px-5 pb-16 sm:px-7">
      <div className="mx-auto w-full max-w-[640px] overflow-hidden rounded-md border border-edge">
        <div className="flex h-9 items-center bg-surface-raised px-3.5">
          <div className="flex gap-1.5">
            <span className="h-2.5 w-2.5 rounded-full bg-[#d4d4d8] dark:bg-[#3a3a3a]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#d4d4d8] dark:bg-[#3a3a3a]" />
            <span className="h-2.5 w-2.5 rounded-full bg-[#d4d4d8] dark:bg-[#3a3a3a]" />
          </div>
          <span className="flex-1 text-center font-mono text-[11px] text-faint">~/myproject</span>
          <div className="w-[34px]" />
        </div>
        <div className="min-h-[160px] overflow-x-auto bg-surface px-[18px] py-5">
          {script.map((line, index) => (
            <div
              key={index}
              className={`whitespace-pre font-mono text-xs leading-loose transition-opacity duration-[120ms] ${
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
          <div className="flex justify-end pt-2">
            <button
              type="button"
              onClick={() => setRunId((id) => id + 1)}
              className="font-mono text-[11px] text-faint transition-colors hover:text-muted"
            >
              ↺ replay
            </button>
          </div>
        </div>
      </div>
    </section>
  )
}
