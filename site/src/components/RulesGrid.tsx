import { rules, type RuleSeverity } from '../lib/rules'

const severityGlyph: Record<RuleSeverity, { glyph: string; className: string }> = {
  error: { glyph: '◉', className: 'text-error' },
  warning: { glyph: '⚠', className: 'text-warn' },
  info: { glyph: '○', className: 'text-faint' },
}

export function RulesGrid() {
  return (
    <section id="rules" className="border-t border-edge px-7 py-16 md:px-14 md:py-20">
      <h2 className="text-[26px] font-bold tracking-[-0.025em] text-primary md:text-[30px]">
        17 rules, out of the box.
      </h2>
      <p className="mt-3 max-w-[52ch] text-[15px] text-secondary">
        No config required. Override anything in{' '}
        <code className="font-mono text-primary">scour.toml</code>.
      </p>

      <div className="mt-10 grid grid-cols-1 gap-x-14 sm:grid-cols-2">
        {rules.map(([name, severity]) => {
          const sev = severityGlyph[severity]
          return (
            <div
              key={name}
              className="flex items-center justify-between border-b border-edge-muted py-2 last:border-b-0 sm:[&:nth-last-child(-n+2)]:border-b-0"
            >
              <span className="font-mono text-[12.5px] text-secondary">{name}</span>
              <span className={`font-mono text-[11px] ${sev.className}`}>
                {sev.glyph} {severity}
              </span>
            </div>
          )
        })}
      </div>

      <p className="mt-8 text-[13.5px] text-muted">
        Run <code className="font-mono text-secondary">scour rules</code> to list them with
        active config overrides. Run{' '}
        <code className="font-mono text-secondary">scour explain &lt;rule&gt;</code> for
        details.
      </p>
    </section>
  )
}
