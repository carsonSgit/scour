import { loader } from 'fumadocs-core/source'
import { defineDocs } from 'fumadocs-mdx/macro'

export const docs = defineDocs({
  dir: 'content/docs',
})

const base = import.meta.env.BASE_URL.replace(/\/$/, '')

export const source = loader({
  baseUrl: `${base}/docs`,
  source: docs.toFumadocsSource(),
})
