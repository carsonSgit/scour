import { DOCS_URL } from '../lib/router'

export function Nav() {
  return (
    <header className="flex h-[52px] items-center justify-between border-b border-edge px-7 md:px-14">
      <a href="#" className="text-[17px] font-bold tracking-[-0.03em] text-primary">
        scour
      </a>
      <nav className="flex items-center gap-7 text-[14px]">
        <a href="#rules" className="text-muted transition-colors hover:text-primary">
          Rules
        </a>
        <a href={DOCS_URL} className="text-muted transition-colors hover:text-primary">
          Documentation
        </a>
        <a
          href="https://github.com/carsonSgit/scour"
          target="_blank"
          rel="noreferrer"
          className="text-muted transition-colors hover:text-primary"
        >
          GitHub ↗
        </a>
      </nav>
    </header>
  )
}
