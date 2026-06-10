import { useState } from 'react'
import { Check, Copy } from 'lucide-react'

const INSTALL_COMMAND =
  'curl -fsSL https://raw.githubusercontent.com/carsonSgit/scour/main/scripts/install.sh | sh'

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
    <section id="hero" className="relative px-5 pb-[72px] pt-20 sm:px-7">
      <div aria-hidden className="dither pointer-events-none absolute inset-0 hidden dark:block" />
      <div aria-hidden className="dither-light pointer-events-none absolute inset-0 dark:hidden" />
      <div className="relative mx-auto w-full max-w-[560px]">
        <p className="font-mono text-[11px] tracking-[2px] text-faint">v0.2.0</p>
        <h1 className="mt-5 text-[26px] font-bold leading-[1.15] tracking-[-0.03em] text-primary sm:text-[32px]">
          Pre-merge hygiene,
          <br />
          before it hits CI.
        </h1>
        <p className="mt-4 max-w-[380px]">
          Scour catches leftover debug code, config drift, and lockfile problems in
          seconds — 13 rules, zero config required.
        </p>
        <div className="mt-8 flex flex-wrap items-center gap-3.5">
          <code className="flex max-w-full items-center gap-3 rounded bg-surface px-4 py-2.5 font-mono text-[13px] text-accent">
            <span className="overflow-x-auto whitespace-nowrap">{INSTALL_COMMAND}</span>
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
