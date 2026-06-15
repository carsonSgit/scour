import { Nav } from './components/Nav'
import { Hero } from './components/Hero'
import { TerminalDemo } from './components/TerminalDemo'
import { RulesGrid } from './components/RulesGrid'
import { GithubAction } from './components/GithubAction'
import { Footer } from './components/Footer'

export default function App() {
  return (
    <div className="relative isolate min-h-screen overflow-hidden bg-background">
      <div aria-hidden className="pointer-events-none absolute inset-0 -z-10 overflow-hidden">
        <div className="dither-band">
          <div className="dither-dots" />
        </div>
      </div>
      <Nav />
      <main>
        <Hero />
        <TerminalDemo />
        <RulesGrid />
        <GithubAction />
      </main>
      <Footer />

      <div aria-hidden className="crt-scanlines fx-flicker pointer-events-none fixed inset-0 z-[60]" />
      <div aria-hidden className="crt-roll pointer-events-none z-[60]" />
    </div>
  )
}
