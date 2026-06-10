import { Nav } from './components/Nav'
import { Hero } from './components/Hero'
import { TerminalDemo } from './components/TerminalDemo'
import { RulesGrid } from './components/RulesGrid'
import { GithubAction } from './components/GithubAction'
import { Footer } from './components/Footer'

export default function App() {
  return (
    <div className="min-h-screen bg-background">
      <Nav />
      <main>
        <Hero />
        <TerminalDemo />
        <RulesGrid />
        <GithubAction />
      </main>
      <Footer />
    </div>
  )
}
