import { createContext, useContext, useEffect, useMemo, useState, type ComponentProps, type MouseEvent, type ReactNode } from 'react'

/* Minimal history-based SPA router: just enough to move between the landing
   page and /docs/* without pulling in a routing dependency. Fumadocs'
   FrameworkProvider consumes this through the hooks below. */

export interface Router {
  pathname: string
  push: (to: string) => void
  refresh: () => void
}

const RouterContext = createContext<Router | null>(null)

const NAVIGATE_EVENT = 'scour:navigate'

function currentPathname(): string {
  return decodeURIComponent(window.location.pathname)
}

export function RouterProvider({ children }: { children: ReactNode }) {
  const [pathname, setPathname] = useState(currentPathname)

  useEffect(() => {
    const onNavigate = () => setPathname(currentPathname())
    window.addEventListener('popstate', onNavigate)
    window.addEventListener(NAVIGATE_EVENT, onNavigate)
    return () => {
      window.removeEventListener('popstate', onNavigate)
      window.removeEventListener(NAVIGATE_EVENT, onNavigate)
    }
  }, [])

  const router = useMemo<Router>(
    () => ({
      pathname,
      push(to) {
        history.pushState(null, '', to)
        setPathname(decodeURIComponent(to))
        window.scrollTo(0, 0)
      },
      refresh() {
        window.dispatchEvent(new Event(NAVIGATE_EVENT))
      },
    }),
    [pathname],
  )

  return <RouterContext value={router}>{children}</RouterContext>
}

export function useRouter(): Router {
  const router = useContext(RouterContext)
  if (!router) throw new Error('useRouter must be used inside <RouterProvider>')
  return router
}

export function usePathname(): string {
  return useRouter().pathname
}

/* Fumadocs docs links start with /docs; everything else keeps native
   browser behavior (anchors, external targets, plain hrefs). */
export function RouterLink({ href, prefetch, onClick, ...props }: ComponentProps<'a'> & { prefetch?: boolean }) {
  const { push } = useRouter()

  function handleClick(event: MouseEvent<HTMLAnchorElement>) {
    onClick?.(event)
    if (event.defaultPrevented) return
    if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey || event.button !== 0) return
    if (!href?.startsWith('/docs')) return
    event.preventDefault()
    push(href)
  }

  return <a href={href} onClick={handleClick} {...props} />
}

/* Sharing the base path with src/lib/docs and every internal link. */
export const BASE_URL = import.meta.env.BASE_URL.replace(/\/$/, '')
export const DOCS_URL = `${BASE_URL}/docs`
export const DOCS_ROOT = DOCS_URL
