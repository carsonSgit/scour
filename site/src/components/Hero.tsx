import { useState } from 'react'
import { Check, Copy } from 'lucide-react'
import { BRAND_GRADIENT } from '../lib/brand'
import { GlitchHeading } from './GlitchHeading'

const INSTALL_COMMAND =
  'curl -fsSL https://raw.githubusercontent.com/carsonSgit/scour/main/scripts/install.sh | sh'

const HEADLINE_GHOST = (
  <>
    Pre-merge hygiene,
    <br />
    before it hits CI.
  </>
)

const HEADING_CLS = 'text-[clamp(1.9rem,5vw,2.75rem)] font-bold leading-[1.08] tracking-[-0.035em]'

function CopyButton() {
  const [copied, setCopied] = useState(false)

  async function copy() {
    await navigator.clipboard.writeText(INSTALL_COMMAND)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <button
      type="button"
      aria-label="Copy install command"
      onClick={copy}
      className="shrink-0 text-muted transition-colors hover:text-accent"
    >
      {copied ? <Check size={14} /> : <Copy size={14} />}
    </button>
  )
}

export function Hero() {
  return (
    <section id="hero" className="relative overflow-hidden px-5 pb-[72px] pt-20 sm:px-7">
      <div aria-hidden className="dither-mask pointer-events-none absolute inset-x-0 -top-[52px] bottom-0">
        <div className="dither-base absolute inset-0" />
      </div>

      <div
        aria-hidden
        className="pointer-events-none absolute -left-10 -top-20 h-[280px] w-[480px] max-w-[92vw] rounded-full opacity-25 blur-[90px]"
        style={{ backgroundImage: BRAND_GRADIENT }}
      />

      <div className="relative mx-auto w-full max-w-[640px]">
        <p className="font-mono text-[11px] uppercase tracking-[3px] text-muted">
          scour <span className="text-faint">//</span> pre-merge scan
        </p>

        <div className="mt-5">
          <GlitchHeading as="h1" className={`${HEADING_CLS} text-primary`} ghost={HEADLINE_GHOST}>
            Pre-merge hygiene,
            <br />
            <span className="bg-clip-text text-transparent" style={{ backgroundImage: BRAND_GRADIENT }}>
              before it hits CI.
            </span>
          </GlitchHeading>
        </div>

        <p className="mt-4 max-w-[380px]">
          Scour catches leftover debug code, config drift, and lockfile problems in
          seconds — 13 rules, zero config required.
        </p>

        <div className="mt-8 flex flex-wrap items-center gap-3.5">
          <code className="flex w-full items-center gap-3 rounded bg-surface px-4 py-2.5 font-mono text-[13px] text-accent">
            <span className="min-w-0 whitespace-normal break-all">{INSTALL_COMMAND}</span>
            <CopyButton />
          </code>
          <p className="text-[13px] text-muted">
            or use the{' '}
            <a
              href="#github-action"
              className="text-secondary underline underline-offset-2 transition-colors hover:text-primary"
            >
              GitHub Action →
            </a>
          </p>
        </div>
      </div>
    </section>
  )
}
