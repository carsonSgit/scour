import { Win } from './Win'

export function Triage() {
  return (
    <section className="border-t border-edge px-7 py-16 md:px-14 md:py-20">
      <div className="grid items-center gap-12 lg:grid-cols-[0.9fr_1.1fr]">
        <div>
          <h2 className="text-[clamp(2rem,4vw,2.75rem)] font-bold leading-[1.08] tracking-[-0.03em] text-primary">
            Know what
            <br />
            to fix first.
          </h2>
          <p className="mt-5 max-w-[38ch] text-[17px] leading-normal text-secondary">
            Group findings by priority. Review a patch before applying supported fixes.
          </p>
          <div className="mt-7 flex flex-wrap items-center gap-7">
            <a
              href="https://github.com/carsonSgit/scour#triage"
              target="_blank"
              rel="noreferrer"
              className="text-[15px] font-medium text-primary transition-opacity hover:opacity-70"
            >
              Explore triage <span className="text-muted">→</span>
            </a>
            <a
              href="https://github.com/carsonSgit/scour#automation"
              target="_blank"
              rel="noreferrer"
              className="text-[15px] font-medium text-primary transition-opacity hover:opacity-70"
            >
              Preview fixes <span className="text-muted">→</span>
            </a>
          </div>
        </div>

        <Win title="~/my-project">
          <pre className="overflow-x-auto px-[18px] py-4 font-mono text-[12.5px] leading-[1.75] text-primary">
            <code>
              $ scour triage --all{'\n'}
              <span className="text-faint">─────────────────────────────────────</span>{'\n'}
              <span className="text-faint">BLOCKERS (1)</span>{'\n'}
              <span className="text-error">◉</span>  <span className="text-secondary">env-drift</span>            <span className="text-faint">.env.example</span>{'\n'}
              <span className="text-faint">FIX NOW (2)</span>{'\n'}
              <span className="text-warn">⚠</span>  <span className="text-secondary">debugger</span>             <span className="text-faint">src/api.ts:42</span>{'\n'}
              <span className="text-warn">⚠</span>  <span className="text-secondary">console-log</span>          <span className="text-faint">src/utils.ts:18</span>{'\n'}
              <span className="text-faint">REVIEW (1)</span>{'\n'}
              <span className="text-faint">○</span>  <span className="text-secondary">package-lock-drift</span>   <span className="text-faint">package.json</span>{'\n'}
              {'\n'}
              $ scour --fix{'\n'}
              <span className="text-ok">writes scour-fix.patch</span>
            </code>
          </pre>
        </Win>
      </div>
    </section>
  )
}
