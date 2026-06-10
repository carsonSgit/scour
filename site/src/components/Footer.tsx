export function Footer() {
  return (
    <footer className="flex items-center justify-between border-t border-edge px-5 py-5 sm:px-7">
      <span className="font-mono text-xs text-faint">scour v0.2.0</span>
      <span className="text-xs text-faint">
        MIT ·{' '}
        <a
          href="https://github.com/carsonSgit/scour"
          target="_blank"
          rel="noreferrer"
          className="transition-colors hover:text-muted"
        >
          GitHub ↗
        </a>
      </span>
    </footer>
  )
}
