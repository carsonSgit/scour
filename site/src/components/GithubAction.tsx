import { GlitchHeading } from './GlitchHeading'

const inputs = ['since', 'staged', 'all', 'format', 'fail-on', 'config', 'version', 'exit-zero', 'triage']

export function GithubAction() {
  return (
    <section id="github-action" className="px-5 py-16 sm:px-7">
      <div className="mx-auto w-full max-w-[560px]">
        <GlitchHeading as="h2" className="text-lg font-semibold tracking-[-0.02em] text-primary">
          Drop it in CI.
        </GlitchHeading>
        <p className="mt-2 mb-5">
          One step. Fails the build on errors, annotates warnings inline.
        </p>
        <pre className="overflow-x-auto rounded bg-surface px-5 py-[18px] font-mono text-xs leading-loose">
          <code>
            <span className="text-muted">- </span>
            <span className="text-info">uses</span>
            <span className="text-muted">: </span>
            <span className="text-ok">carsonSgit/scour@v1</span>
            {'\n'}
            <span className="text-muted">  </span>
            <span className="text-info">with</span>
            <span className="text-muted">:</span>
            {'\n'}
            <span className="text-muted">    </span>
            <span className="text-info">fail-on</span>
            <span className="text-muted">: </span>
            <span className="text-ok">warning</span>
            {'\n'}
            <span className="text-muted">    </span>
            <span className="text-info">triage</span>
            <span className="text-muted">: </span>
            <span className="text-ok">"true"</span>
          </code>
        </pre>
        <p className="mt-4 text-[13px]">
          <span className="text-muted">Inputs: </span>
          {inputs.map((name) => (
            <code key={name} className="mr-2 font-mono text-faint">
              {name}
            </code>
          ))}
        </p>
      </div>
    </section>
  )
}
