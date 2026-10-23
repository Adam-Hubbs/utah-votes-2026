import { HashRouter, Route, Routes, useLocation } from 'react-router-dom'
import { useEffect } from 'react'
import { SiteProvider } from './data/site'
import { Layout } from './components/Layout'
import { Overview } from './pages/Overview'
import { ResultsPage } from './pages/Results'
import { PollsPage } from './pages/Polls'
import { RacePage } from './pages/Race'
import { ForecastsPage } from './pages/Forecasts'
import { HistoryPage } from './pages/History'
import { DemographicsPage } from './pages/Demographics'
import { MethodologyPage } from './pages/Methodology'
import { NationalPage } from './pages/National'

function ScrollTop() {
  const { pathname } = useLocation()
  useEffect(() => { window.scrollTo(0, 0) }, [pathname])
  return null
}

export function App() {
  return (
    <HashRouter>
      <SiteProvider>
        <ScrollTop />
        <Layout>
          <Routes>
            <Route path="/" element={<Overview />} />
            <Route path="/results" element={<ResultsPage />} />
            <Route path="/results/:electionId/:contestId" element={<ResultsPage />} />
            <Route path="/polls" element={<PollsPage />} />
            <Route path="/race/:contestId" element={<RacePage />} />
            <Route path="/forecasts" element={<ForecastsPage />} />
            <Route path="/history" element={<HistoryPage />} />
            <Route path="/demographics" element={<DemographicsPage />} />
            <Route path="/national" element={<NationalPage />} />
            <Route path="/methodology" element={<MethodologyPage />} />
            <Route path="*" element={<Overview />} />
          </Routes>
        </Layout>
      </SiteProvider>
    </HashRouter>
  )
}
