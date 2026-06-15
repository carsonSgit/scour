import type { ReactNode } from 'react'

type Props = {
  as?: 'h1' | 'h2'
  className?: string
  children: ReactNode
  ghost?: ReactNode
}

export function GlitchHeading({ as = 'h2', className = '', children, ghost }: Props) {
  const Tag = as
  const ghosted = ghost ?? children
  return (
    <div className="relative inline-block">
      <Tag className={`relative ${className}`}>{children}</Tag>
      <Tag
        aria-hidden
        className={`fx-glitch pointer-events-none absolute inset-0 text-error opacity-50 mix-blend-screen ${className}`}
        style={{ transform: 'translateX(-1.5px)' }}
      >
        {ghosted}
      </Tag>
      <Tag
        aria-hidden
        className={`fx-glitch pointer-events-none absolute inset-0 text-info opacity-50 mix-blend-screen ${className}`}
        style={{ transform: 'translateX(1.5px)', animationDelay: '0.2s' }}
      >
        {ghosted}
      </Tag>
    </div>
  )
}
