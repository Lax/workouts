import { useTheme } from '@workouts/core'
import { useMemo } from 'react'
import { useSimpleStore } from '../store'
import { Header } from './Header'
import { SummaryCardGrid } from './SummaryCardGrid'
import { SummaryFilterBar } from './SummaryFilterBar'
import { SummaryLifeView } from './SummaryLifeView'

export function SummaryView() {
  const { config } = useTheme()
  const siteConfig = config?.site as Record<string, unknown> | undefined

  const SITE = useMemo(
    () => ({
      title: (siteConfig?.title as string) || 'Workouts',
      url: (siteConfig?.url as string) || '/',
      logo: (siteConfig?.logo as string | null) || null,
      navLinks: (siteConfig?.navLinks as { name: string; url: string }[]) || [],
    }),
    [siteConfig],
  )

  const summaryInterval = useSimpleStore((s) => s.summaryInterval)

  return (
    <>
      <Header config={SITE} />
      <div className="summary-view">
        <SummaryFilterBar />
        {summaryInterval === 'life' ? <SummaryLifeView /> : <SummaryCardGrid />}
      </div>
    </>
  )
}
