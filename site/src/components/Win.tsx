import type { ReactNode } from 'react'

type Props = {
  title: string
  children: ReactNode
  className?: string
}

/* macOS-style window chrome shared by every terminal and code window on the
   page, so all boxes read as one system: same radius, same border tier, same
   bar, same dot colors. */
export function Win({ title, children, className = '' }: Props) {
  return (
    <div
      className={`overflow-hidden rounded-[10px] border border-edge-muted bg-surface shadow-[0_1px_2px_rgba(0,0,0,0.03),0_10px_30px_rgba(20,20,18,0.06)] ${className}`}
    >
      <div className="flex items-center gap-3 border-b border-edge-muted bg-surface-raised px-3.5 py-2">
        <span className="flex gap-1.5">
          <i className="block h-[9px] w-[9px] rounded-full border border-[#e04b3d]/40 bg-[#f16a5d]" />
          <i className="block h-[9px] w-[9px] rounded-full border border-[#e2a52f]/40 bg-[#f5bd4f]" />
          <i className="block h-[9px] w-[9px] rounded-full border border-[#4fae43]/40 bg-[#61c554]" />
        </span>
        <span className="font-mono text-[12px] text-muted">{title}</span>
      </div>
      {children}
    </div>
  )
}
