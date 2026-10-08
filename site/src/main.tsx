import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import { DocsShell } from './docs/DocsShell'
import { BASE_URL, RouterProvider, usePathname } from './lib/router'
import './styles/globals.css'

function Root() {
  const pathname = usePathname()
  return pathname.startsWith(`${BASE_URL}/docs`) ? <DocsShell /> : <App />
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider>
      <Root />
    </RouterProvider>
  </React.StrictMode>,
)
