import { rules, type RuleSeverity } from '../lib/rules'

const severityColor: Record<RuleSeverity, string> = {
  error: 'text-error',
  warning: 'text-warn',
  info: 'text-info',
}

export function RulesGrid() {
  return (
    <section className="px-5 py-16 sm:px-7">
      <div className="mx-auto w-full max-w-[600px]">
        <h2 className="text-lg font-semibold tracking-[-0.02em] text-primary">
          13 rules, out of the box.
        </h2>
        <p className="mt-2">
          No config required. Override anything in{' '}
          <code className="rounded bg-surface px-1.5 py-0.5 font-mono text-[13px] text-secondary">
            scour.toml
          </code>
          .
        </p>
        <div className="mt-8 grid grid-cols-1 gap-x-8 sm:grid-cols-2">
          {rules.map(([name, severity]) => (
            <div
              key={name}
              className="flex items-center justify-between border-b border-edge-muted py-1.5 last:border-b-0 sm:[&:nth-last-child(-n+2)]:border-b-0"
            >
              <span className="font-mono text-xs text-muted">{name}</span>
              <span className={`font-mono text-[11px] ${severityColor[severity]}`}>
                {severity}
              </span>
            </div>
          ))}
        </div>
        <p className="mt-6 text-[13px] text-muted">
          Run <code className="font-mono">scour rules</code> to list them with active
          config overrides. Run <code className="font-mono">scour explain &lt;rule&gt;</code>{' '}
          for details.
        </p>
      </div>
    </section>
  )
}
