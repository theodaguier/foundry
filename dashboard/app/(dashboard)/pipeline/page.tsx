import { getStageDurations, getBuildAttemptsDistribution, getFailureBreakdown, getSuccessRateByModel, getTokenCostTimeline, getAttemptsVsDuration } from "@/lib/queries"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { StageBarChart } from "@/components/charts/stage-bar-chart"
import { FailurePieChart } from "@/components/charts/failure-pie-chart"
import { ModelSuccessChart } from "@/components/charts/model-success-chart"
import { TokenCostChart } from "@/components/charts/token-cost-chart"
import { AttemptsDistributionChart } from "@/components/charts/attempts-distribution-chart"
import { AttemptsScatterChart } from "@/components/charts/scatter-chart"

export const revalidate = 60

export default async function PipelinePage() {
  const [stages, attempts, failures, models, tokens, scatter] = await Promise.all([
    getStageDurations(),
    getBuildAttemptsDistribution(),
    getFailureBreakdown(),
    getSuccessRateByModel(),
    getTokenCostTimeline(30),
    getAttemptsVsDuration(),
  ])

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-base font-normal tracking-wide">Pipeline analytics</h1>
        <p className="text-xs text-muted-foreground mt-0.5">Performance, costs and failure analysis</p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <Card>
          <CardHeader>
            <CardTitle>Avg stage duration</CardTitle>
            <CardDescription>Successful generations only</CardDescription>
          </CardHeader>
          <CardContent className="p-4">
            <StageBarChart data={stages} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Build attempts distribution</CardTitle>
            <CardDescription>How many attempts it takes to succeed</CardDescription>
          </CardHeader>
          <CardContent className="p-4">
            <AttemptsDistributionChart data={attempts} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Failure stage breakdown</CardTitle>
            <CardDescription>Where in the pipeline things fail</CardDescription>
          </CardHeader>
          <CardContent className="p-4">
            <FailurePieChart data={failures} />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Success rate by model</CardTitle>
            <CardDescription>Min 1 generation to appear</CardDescription>
          </CardHeader>
          <CardContent className="p-4">
            <ModelSuccessChart data={models} />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Tokens & cost — last 30 days</CardTitle>
            <CardDescription>Stacked tokens (left axis) + cost overlay (right axis)</CardDescription>
          </CardHeader>
          <CardContent className="p-4">
            <TokenCostChart data={tokens} />
          </CardContent>
        </Card>

        <Card className="md:col-span-2">
          <CardHeader>
            <CardTitle>Build attempts vs total duration</CardTitle>
            <CardDescription>Correlation — successful generations only</CardDescription>
          </CardHeader>
          <CardContent className="p-4">
            <AttemptsScatterChart data={scatter} />
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
