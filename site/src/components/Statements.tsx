import { Win } from './Win'

/* The two-cell statement section: a bold claim with its continuation in the
   secondary weight, each anchored by a real code window underneath. */
export function Statements() {
  return (
    <section className="border-t border-edge">
      <div className="grid lg:grid-cols-2">
        <div className="py-12 pl-7 pr-7 md:py-14 md:pl-14 md:pr-12 lg:border-r lg:border-edge">
          <h2 className="text-[26px] font-bold leading-snug tracking-[-0.025em] text-primary md:text-[34px] lg:leading-[1.22]">
            Catch what slips through.{' '}
            <span className="font-normal text-muted">
              Debug statements, focused tests, and files that shouldn't be committed.
            </span>
          </h2>
          <div className="mt-10">
            <Win title="src/api.ts">
              <pre className="overflow-x-auto px-[18px] py-4 font-mono text-[12.5px] leading-[1.75] text-primary">
                <code>
                  <span className="text-faint">38</span>  <span className="text-[#6558f5] font-medium">const</span> user = <span className="text-[#6558f5] font-medium">await</span> getUser(id);{'\n'}
                  <span className="text-faint">39</span>  <span className="hl-err">debugger;</span>{'\n'}
                  <span className="text-faint">40</span>  <span className="text-[#6558f5] font-medium">return</span> res.json(user);{'\n'}
                  <span className="text-faint">41</span> {'}'}
                </code>
              </pre>
            </Win>
          </div>
          <p className="mt-6 max-w-[44ch] text-[13.5px] leading-relaxed text-muted">
            17 rules cover source hygiene across nine languages — plus repo checks for
            env files, generated output, and Docker context.
          </p>
        </div>

        <div className="border-t border-edge py-12 pl-7 pr-7 md:py-14 md:pr-14 md:pl-12 lg:border-t-0">
          <h2 className="text-[26px] font-bold leading-snug tracking-[-0.025em] text-primary md:text-[34px] lg:leading-[1.22]">
            Keep your repo in sync.{' '}
            <span className="font-normal text-muted">
              Check env contracts, documented commands, CI, and lockfiles.
            </span>
          </h2>
          <div className="mt-10">
            <Win title=".env.example">
              <pre className="overflow-x-auto px-[18px] py-4 font-mono text-[12.5px] leading-[1.75] text-primary">
                <code>
                  <span className="text-faint">1</span>  API_URL=<span className="text-ok">https://api.example.com</span>{'\n'}
                  <span className="text-faint">2</span>  <span className="hl-warn">DATABASE_URL=<span className="text-ok">postgres://localhost</span></span>{'\n'}
                  <span className="text-faint">3</span>  REDIS_URL=<span className="text-ok">redis://localhost:6379</span>{'\n'}
                  <span className="text-faint">4</span>  NODE_ENV=<span className="text-ok">development</span>
                </code>
              </pre>
            </Win>
          </div>
          <p className="mt-6 max-w-[44ch] text-[13.5px] leading-relaxed text-muted">
            <code className="font-mono">env-drift</code> compares tracked env files against
            their example contracts, so missing keys surface before they surface in staging.
          </p>
        </div>
      </div>
    </section>
  )
}
