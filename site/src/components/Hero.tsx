import { TerminalDemo } from './TerminalDemo'
import { DOCS_URL } from '../lib/router'

const INSTALL_URL = 'https://raw.githubusercontent.com/carsonSgit/scour/main/scripts/install.sh'

export function Hero() {
  return (
    <section className="relative overflow-hidden px-7 py-14 md:py-20 md:px-14">
      <div aria-hidden className="dotted pointer-events-none absolute inset-0" />

      <div className="relative grid items-center gap-12 lg:grid-cols-[0.92fr_1.08fr]">
        <div>
          <p className="text-[15px] text-muted">Pre-merge checks for your repository.</p>
          <h1 className="mt-6 text-[clamp(3rem,7vw,4.75rem)] font-bold leading-[0.98] tracking-[-0.035em] text-primary">
            Leave less
            <br />
            behind.
          </h1>
          <p className="mt-6 max-w-[38ch] text-[17px] leading-normal text-secondary">
            Find debug code, config drift, and lockfile mistakes before you merge.
          </p>
        </div>

        <TerminalDemo />
      </div>

      <div className="relative mt-10 flex flex-wrap items-center gap-7">
        <a
          href={INSTALL_URL}
          target="_blank"
          rel="noreferrer"
          className="inline-flex items-center gap-2 rounded-[9px] bg-accent px-5 py-2.5 text-[15px] font-medium text-background shadow-[0_1px_2px_rgba(0,0,0,0.08)] transition-colors hover:bg-accent-hover"
        >
          Install scour <span className="opacity-65">↗</span>
        </a>
        <a
          href={DOCS_URL}
          className="text-[15px] font-medium text-primary transition-opacity hover:opacity-70"
        >
          Read the docs <span className="text-muted">→</span>
        </a>
      </div>
    </section>
  )
}
