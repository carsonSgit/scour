import { useEffect, type ComponentProps } from 'react'
import { FrameworkProvider } from 'fumadocs-core/framework'
import { RootProvider } from 'fumadocs-ui/provider/base'
import { DocsLayout } from 'fumadocs-ui/layouts/docs'
import { DocsBody, DocsDescription, DocsPage, DocsTitle } from 'fumadocs-ui/layouts/docs/page'
import defaultMdxComponents from 'fumadocs-ui/mdx'
import { source } from '../lib/source'
import { DOCS_ROOT, RouterLink, useRouter, type Router } from '../lib/router'

const baseOptions = {
  nav: {
    title: 'scour',
    url: '/',
  },
  githubUrl: 'https://github.com/carsonSgit/scour',
}

const frameworkProps = {
  useParams: () => ({}),
  useRouter: (): Router => useRouter(),
  Link: RouterLink as unknown as ComponentProps<typeof FrameworkProvider>['Link'],
  Image: undefined,
}

function Content({ pathname }: { pathname: string }) {
  const rest = pathname.startsWith(DOCS_ROOT) ? pathname.slice(DOCS_ROOT.length) : pathname
  const slugs = decodeURIComponent(rest).split('/').filter((v) => v.length > 0)
  const page = source.getPage(slugs)

  if (!page) {
    return (
      <DocsPage>
        <DocsTitle>Not found</DocsTitle>
        <DocsBody>
          <p>
            This page doesn't exist. <RouterLink href="/docs">Back to docs →</RouterLink>
          </p>
        </DocsBody>
      </DocsPage>
    )
  }

  return <DocPageContent page={page} />
}

function DocPageContent({ page }: { page: NonNullable<ReturnType<typeof source.getPage>> }) {
  const { body: Mdx, toc, title, description } = page.data

  useEffect(() => {
    window.scrollTo(0, 0)
  }, [page.path])

  return (
    <DocsPage toc={toc}>
      <title>{title}</title>
      <meta name="description" content={description} />
      <DocsTitle>{title}</DocsTitle>
      <DocsDescription>{description}</DocsDescription>
      <DocsBody>
        <Mdx components={defaultMdxComponents} />
      </DocsBody>
    </DocsPage>
  )
}

export function DocsShell() {
  const { pathname } = useRouter()

  return (
    <RootProvider theme={{ defaultTheme: 'light', enableSystem: false }} search={{ enabled: false }}>
      <FrameworkProvider usePathname={() => pathname} {...frameworkProps}>
        <DocsLayout {...baseOptions} tree={source.getPageTree()}>
          <Content pathname={pathname} />
        </DocsLayout>
      </FrameworkProvider>
    </RootProvider>
  )
}
