import { useState } from 'react'
import { Check, Copy } from 'lucide-react'

/* Shared clipboard affordance for the bare command lines on the page. */
export function CopyButton({ text, className = '' }: { text: string; className?: string }) {
  const [copied, setCopied] = useState(false)

  async function copy() {
    await navigator.clipboard.writeText(text)
    setCopied(true)
    setTimeout(() => setCopied(false), 1500)
  }

  return (
    <button
      type="button"
      aria-label="Copy install command"
      onClick={copy}
      className={`shrink-0 text-faint transition-colors hover:text-primary ${className}`}
    >
      {copied ? <Check size={14} /> : <Copy size={14} />}
    </button>
  )
}
