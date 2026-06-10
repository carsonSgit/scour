import { describe, expect, it } from 'vitest'
import { CURSOR_HIDE_MS, CURSOR_SHOW_MS, RESTART_PAUSE_MS, script } from '../src/lib/terminalScript'

describe('terminal script', () => {
  it('starts with the command line at delay 0', () => {
    expect(script[0].delay).toBe(0)
    expect(script[0].segments.map((s) => s.text).join('')).toBe('❯ scour --all')
  })

  it('has strictly increasing delays', () => {
    for (let i = 1; i < script.length; i++) {
      expect(script[i].delay).toBeGreaterThan(script[i - 1].delay)
    }
  })

  it('shows the cursor between the command and the first finding', () => {
    expect(CURSOR_SHOW_MS).toBeGreaterThan(script[0].delay)
    expect(CURSOR_HIDE_MS).toBeLessThanOrEqual(script[1].delay)
  })

  it('summarizes exactly the findings shown', () => {
    const glyphs = script.flatMap((line) => line.segments.filter((s) => s.text.trim() === '✗' || s.text.trim() === '⚠'))
    const errors = glyphs.filter((s) => s.text.trim() === '✗').length
    const warnings = glyphs.filter((s) => s.text.trim() === '⚠').length
    const summary = script[script.length - 1].segments.map((s) => s.text).join('')
    expect(summary).toBe(`${errors + warnings} issues · ${errors} errors · ${warnings} warnings`)
  })

  it('pauses 4s before restarting', () => {
    expect(RESTART_PAUSE_MS).toBe(4000)
  })
})
