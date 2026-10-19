import { CopyButton } from '../lib/copy'

const INSTALL_COMMAND =
  'curl -fsSL https://raw.githubusercontent.com/carsonSgit/scour/main/scripts/install.sh | sh'

export function InstallBar() {
  return (
    <section id="install" className="border-t border-edge px-7 pb-12 pt-5 md:px-14">
      <div className="flex items-center gap-3 overflow-x-auto rounded-[10px] border border-edge bg-surface px-4 py-3 shadow-[0_1px_2px_rgba(0,0,0,0.03)]">
        <span className="shrink-0 font-mono text-[12.5px] text-faint">$&nbsp;</span>
        <span className="min-w-0 whitespace-nowrap font-mono text-[12.5px] text-secondary">
          curl -fsSL https://raw.githubusercontent.com/carsonSgit/scour/main/scripts/install.sh | sh
        </span>
        <CopyButton text={INSTALL_COMMAND} className="ml-auto" />
      </div>
      <p className="mt-3 font-mono text-[11.5px] tracking-wide text-faint">
        17 configurable rules · one static binary · MIT licensed
      </p>
    </section>
  )
}
