import { Moon, Sun } from 'lucide-react'
import { useTheme } from '../lib/useTheme'

export function Nav() {
  const { theme, toggle } = useTheme()

  return (
    <header className="relative z-10 flex h-[52px] items-center justify-between px-7 md:px-12 xl:px-16">
      <a href="#" className="text-[15px] font-bold tracking-[-0.3px] text-primary">
        scour
      </a>
      <nav className="flex items-center gap-5 text-[13px]">
        <a
          href="https://github.com/carsonSgit/scour"
          target="_blank"
          rel="noreferrer"
          className="text-muted transition-colors hover:text-secondary"
        >
          GitHub
        </a>
        <a
          href="https://github.com/carsonSgit/scour#readme"
          target="_blank"
          rel="noreferrer"
          className="hidden text-muted transition-colors hover:text-secondary sm:block"
        >
          Docs
        </a>
        <button
          type="button"
          aria-label="Toggle theme"
          onClick={toggle}
          className="flex h-8 w-8 items-center justify-center rounded text-muted transition-colors hover:text-primary"
        >
          {theme === 'dark' ? <Sun size={15} /> : <Moon size={15} />}
        </button>
      </nav>
    </header>
  )
}
