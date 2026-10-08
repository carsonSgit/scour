import { Win } from './Win'

export function GithubAction() {
  return (
    <section id="github-action" className="bg-surface-raised px-7 py-16 md:px-14 md:py-20">
      <div className="grid items-center gap-12 lg:grid-cols-[0.95fr_1.05fr]">
        <Win title=".github/workflows/ci.yml">
          <pre className="overflow-x-auto px-[18px] py-4 font-mono text-[12.5px] leading-[1.75] text-primary">
            <code>
              <span className="text-faint">- </span>
              <span className="text-[#6558f5] font-medium">uses</span>
              <span className="text-faint">: </span>
              <span className="text-ok">carsonSgit/scour@v0.4.5</span>
              {'\n'}  <span className="text-faint">with:</span>
              {'\n'}    <span className="text-[#6558f5] font-medium">version</span>
              <span className="text-faint">: </span>
              <span className="text-ok">v0.4.5</span>
              {'\n'}    <span className="text-[#6558f5] font-medium">fail-on</span>
              <span className="text-faint">: </span>
              <span className="text-ok">warning</span>
              {'\n'}    <span className="text-[#6558f5] font-medium">triage</span>
              <span className="text-faint">: </span>
              <span className="text-ok">"true"</span>
            </code>
          </pre>
        </Win>

        <div>
          <h2 className="text-[clamp(1.75rem,3vw,2.25rem)] font-bold tracking-[-0.03em] text-primary">
            Runs where your merges run.
          </h2>
          <p className="mt-5 max-w-[46ch] text-[17px] leading-normal text-secondary">
            One GitHub Action drop-in. Pin both action and binary, fail on your threshold,
            and ship fixes as reviewable patch artifacts — never direct commits.
          </p>
          <p className="mt-5 max-w-[46ch] text-[13.5px] text-muted">
            Also speaks JSON, SARIF, GitHub annotations, and Code Quality reports for GitLab.
          </p>
        </div>
      </div>
    </section>
  )
}
