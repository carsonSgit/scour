import { useEffect, useState } from 'react'
import { Moon, Sun } from 'lucide-react'
import { useTheme } from '../lib/useTheme'

export function Nav() {
  const { theme, toggle } = useTheme()
  const [scrolled, setScrolled] = useState(false)

  useEffect(() => {
    const hero = document.getElementById('hero')
    if (!hero) return
    const observer = new IntersectionObserver(
      ([entry]) => setScrolled(!entry.isIntersecting),
      { rootMargin: '-52px 0px 0px 0px' },
    )
    observer.observe(hero)
    return () => observer.disconnect()
  }, [])

  return (
    <header
      className={`sticky top-0 z-10 flex h-[52px] items-center justify-between px-7 transition-colors duration-200 md:px-12 xl:px-16 ${
        scrolled ? 'bg-surface-raised/80 backdrop-blur-sm' : 'bg-transparent'
      }`}
    >
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
