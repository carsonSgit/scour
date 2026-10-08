export function Footer() {
  return (
    <footer className="flex flex-col items-center gap-2.5 border-t border-edge px-7 py-5 text-[13px] text-muted sm:flex-row sm:justify-between md:px-14">
      <span className="text-[15px] font-bold tracking-[-0.03em] text-primary">scour</span>
      <span className="font-mono text-[12px] tracking-wide">CLI · GitHub Action · MIT licensed</span>
      <a
        href="https://github.com/carsonSgit/scour"
        target="_blank"
        rel="noreferrer"
        className="transition-colors hover:text-primary"
      >
        GitHub ↗
      </a>
    </footer>
  )
}
