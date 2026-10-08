import { Nav } from './components/Nav'
import { Hero } from './components/Hero'
import { InstallBar } from './components/InstallBar'
import { Statements } from './components/Statements'
import { Triage } from './components/Triage'
import { RulesGrid } from './components/RulesGrid'
import { GithubAction } from './components/GithubAction'
import { Footer } from './components/Footer'

/* One centered rail with hairline sides carries the whole page; sections
   stack against hairline top borders with no gaps between them. */
export default function App() {
  return (
    <div className="min-h-screen bg-background">
      <div className="mx-auto max-w-[1128px] lg:border-x lg:border-edge">
        <Nav />
        <main>
          <Hero />
          <InstallBar />
          <Statements />
          <Triage />
          <RulesGrid />
          <GithubAction />
          <section className="border-t border-edge px-7 py-16 md:px-14 md:py-20">
            <div className="flex flex-wrap items-center justify-between gap-10">
              <h2 className="text-[clamp(1.875rem,4vw,2.625rem)] font-bold leading-[1.1] tracking-[-0.03em] text-primary">
                Run one scan.
                <br />
                Merge with confidence.
              </h2>
              <div className="flex flex-wrap items-center gap-7">
                <a
                  href="https://raw.githubusercontent.com/carsonSgit/scour/main/scripts/install.sh"
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex items-center gap-2 rounded-[9px] bg-accent px-5 py-2.5 text-[15px] font-medium text-background shadow-[0_1px_2px_rgba(0,0,0,0.08)] transition-colors hover:bg-accent-hover"
                >
                  Install scour <span className="opacity-65">↗</span>
                </a>
                <a
                  href="https://github.com/carsonSgit/scour"
                  target="_blank"
                  rel="noreferrer"
                  className="text-[15px] font-medium text-primary transition-opacity hover:opacity-70"
                >
                  GitHub ↗
                </a>
              </div>
            </div>
          </section>
        </main>
        <Footer />
      </div>
    </div>
  )
}
