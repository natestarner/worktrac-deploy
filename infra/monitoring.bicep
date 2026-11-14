// Production alerts: one action group (who gets told) and the rules that tell it.
//
// Prod only, deliberately. Lower scales to zero, so "no health-metrics line" is its normal state,
// and a red lower is triaged by the deploy pipeline, not by email.
//
// Two kinds of rule, chosen by price (Azure Monitor, eastus, checked 2026-11-14):
//   - Metric alerts: $0.10/month per monitored series, first 10 free. Used for everything the
//     platform already measures (5xx, restarts, memory, database).
//   - Log search alerts over Log Analytics: $0.50/month at a 15-minute frequency, $1.00 at 10,
//     $1.50 at 5. Used only for what lives in the app's own `health-metrics` log line (outbox and
//     connection pool) and for "the app stopped reporting at all".
// Total about $2.50/month.
//
// The `health-metrics` keys are an API (worktrac-source docs/azure-read-only-access.md, "Health
// metrics"): never rename one in the backend without changing the parse below in the same release.
// Each rule's query was run against the live workspace before it shipped: quiet on prod at the
// real thresholds, firing with the thresholds forced low, and `replica-silent` firing on lower
// while it was scaled to zero.

param location string = 'eastus'

@description('Container App the rules watch, e.g. worktrac-backend-prod.')
param appName string

@description('Azure SQL server and database the rules watch.')
param sqlServerName string
param sqlDatabaseName string

@description('Log Analytics workspace the Container Apps environment writes to.')
param workspaceName string = 'worktrac-logs'

@description('Action group name, and the short name (max 12 characters) that SMS and email show.')
param actionGroupName string
@maxLength(12)
param actionGroupShortName string

@description('Who gets the alerts, by email: [{ name, address }].')
param emailReceivers array

resource app 'Microsoft.App/containerApps@2025-07-01' existing = {
  name: appName
}

resource sqlServer 'Microsoft.Sql/servers@2023-08-01' existing = {
  name: sqlServerName
}

resource sqlDatabase 'Microsoft.Sql/servers/databases@2023-08-01' existing = {
  parent: sqlServer
  name: sqlDatabaseName
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: workspaceName
}

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = {
  name: actionGroupName
  location: 'global'
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    emailReceivers: [
      for r in emailReceivers: {
        name: r.name
        emailAddress: r.address
        useCommonAlertSchema: true
      }
    ]
  }
}

// ---------------------------------------------------------------------------------------------
// Metric alerts
// ---------------------------------------------------------------------------------------------

var metricAlerts = [
  {
    name: '${appName}-5xx'
    description: 'The API answered 10 or more requests with a 5xx in 5 minutes. Prod had none at all in the 7 days before this rule (2026-11-07 to 11-14), so this is real breakage: read ContainerAppConsoleLogs_CL for the errors.'
    severity: 1
    scope: app.id
    namespace: 'Microsoft.App/containerApps'
    metric: 'Requests'
    aggregation: 'Total'
    operator: 'GreaterThanOrEqual'
    threshold: 10
    dimensions: [
      { name: 'statusCodeCategory', operator: 'Include', values: [ '5xx' ] }
    ]
    frequency: 'PT5M'
    window: 'PT5M'
  }
  {
    name: '${appName}-restarts'
    description: 'A backend container restarted: a crash, an out-of-memory kill, or failing liveness checks. Zero restarts in the 7 days before this rule. ContainerAppSystemLogs_CL says why. Clears when the restarted replica is replaced (the next deploy).'
    severity: 1
    scope: app.id
    namespace: 'Microsoft.App/containerApps'
    metric: 'RestartCount'
    aggregation: 'Maximum'
    operator: 'GreaterThan'
    threshold: 0
    dimensions: []
    frequency: 'PT5M'
    window: 'PT15M'
  }
  {
    name: '${appName}-memory'
    description: 'Backend memory averaged over 97% of its limit for 15 minutes: close to an out-of-memory kill. Note 85-92% is NORMAL on the 0.5 GiB prod app (the JVM settles there; p50 85%, max 92% over 2026-11-07 to 11-14), which is why the line is this high.'
    severity: 2
    scope: app.id
    namespace: 'Microsoft.App/containerApps'
    metric: 'MemoryPercentage'
    aggregation: 'Average'
    operator: 'GreaterThan'
    threshold: 97
    dimensions: []
    frequency: 'PT5M'
    window: 'PT15M'
  }
  {
    name: '${sqlDatabaseName}-dtu'
    description: 'The production database averaged over 80% of its DTU limit for 15 minutes (Basic tier, 5 DTU). It peaked at 8% in the 7 days before this rule. Sustained, requests slow down and then time out; the Query Store (docs/azure-read-only-access.md) names the statement.'
    severity: 2
    scope: sqlDatabase.id
    namespace: 'Microsoft.Sql/servers/databases'
    metric: 'dtu_consumption_percent'
    aggregation: 'Average'
    operator: 'GreaterThan'
    threshold: 80
    dimensions: []
    frequency: 'PT5M'
    window: 'PT15M'
  }
  {
    name: '${sqlDatabaseName}-storage'
    description: 'The production database is over 80% of its 2 GB maximum size (2% on 2026-11-14). Writes fail once it is full: raise the size or the tier before then.'
    severity: 2
    scope: sqlDatabase.id
    namespace: 'Microsoft.Sql/servers/databases'
    metric: 'storage_percent'
    aggregation: 'Maximum'
    operator: 'GreaterThan'
    threshold: 80
    dimensions: []
    frequency: 'PT1H'
    window: 'PT1H'
  }
]

resource metricRules 'Microsoft.Insights/metricAlerts@2018-03-01' = [
  for a in metricAlerts: {
    name: a.name
    location: 'global'
    properties: {
      description: a.description
      severity: a.severity
      enabled: true
      scopes: [ a.scope ]
      evaluationFrequency: a.frequency
      windowSize: a.window
      autoMitigate: true
      criteria: {
        'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
        allOf: [
          {
            criterionType: 'StaticThresholdCriterion'
            name: 'condition'
            metricNamespace: a.namespace
            metricName: a.metric
            timeAggregation: a.aggregation
            operator: a.operator
            threshold: a.threshold
            dimensions: a.dimensions
          }
        ]
      }
      actions: [
        { actionGroupId: actionGroup.id }
      ]
    }
  }
]

// ---------------------------------------------------------------------------------------------
// Log search alerts over the app's `health-metrics` line (one per replica per minute)
// ---------------------------------------------------------------------------------------------

var healthLines = 'ContainerAppConsoleLogs_CL | where ContainerAppName_s == \'${appName}\' | where Log_s contains \'health-metrics outboxPending=\''
var parseHealth = '| parse Log_s with * \'outboxPending=\' pending:int \' outboxOldestPendingSeconds=\' oldest:long \' outboxFailedLastHour=\' failed:int \' poolActive=\' active:int \' poolIdle=\' idle:int \' poolTotal=\' total:int \' poolMax=\' max:int \' poolWaiting=\' waiting:int *'

var logAlerts = [
  {
    name: '${appName}-email-stuck'
    displayName: 'Prod: email stuck in the outbox'
    description: 'An email has been waiting over 15 minutes to send. That is past the outbox\'s whole ~9.5-minute retry schedule, so retries are not getting it out: ACS refusing, a quota, or the outbox not running.'
    severity: 2
    query: '${healthLines} ${parseHealth} | where oldest > 900'
    frequency: 'PT15M'
    window: 'PT15M'
    // Stateful: one email when it starts, one when it clears.
    autoMitigate: true
    mute: null
  }
  {
    name: '${appName}-email-failed'
    displayName: 'Prod: an email gave up'
    description: 'An outbox row used every retry and was marked FAILED in the last hour. Its reason is on the row and in the admin Activity tab. The app also emails the admin about it; this alert is sent by Azure Monitor, so it arrives even when the app\'s own email is what broke.'
    severity: 2
    query: '${healthLines} ${parseHealth} | where failed > 0'
    frequency: 'PT15M'
    window: 'PT15M'
    // outboxFailedLastHour is a rolling one-hour count, so the condition stays true for an hour
    // after one failure. Stateless + muted for an hour = one email per failure, not four.
    autoMitigate: false
    mute: 'PT1H'
  }
  {
    name: '${appName}-pool-saturated'
    displayName: 'Prod: database connection pool exhausted'
    description: 'Requests waited for a database connection in 3 or more of 5 consecutive minutes on one replica: every connection busy. Requests slow down, then time out.'
    severity: 2
    query: '${healthLines} ${parseHealth} | where waiting > 0 | summarize minutes = count() by bin(TimeGenerated, 5m), ContainerGroupName_s | where minutes >= 3'
    frequency: 'PT15M'
    window: 'PT15M'
    autoMitigate: true
    mute: null
  }
  {
    name: '${appName}-silent'
    displayName: 'Prod: backend stopped reporting'
    description: 'No health-metrics line from the prod backend for 10 minutes. Every running replica writes one a minute, and prod never scales to zero, so the app is down, hung, or not writing logs. Check https://api.huddle.fitness/actuator/health and ContainerAppSystemLogs_CL.'
    severity: 1
    query: '${healthLines} | summarize lines = count() | where lines == 0'
    frequency: 'PT10M'
    window: 'PT10M'
    autoMitigate: true
    mute: null
  }
]

resource logRules 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [
  for a in logAlerts: {
    name: a.name
    location: location
    properties: {
      displayName: a.displayName
      description: a.description
      severity: a.severity
      enabled: true
      scopes: [ workspace.id ]
      evaluationFrequency: a.frequency
      windowSize: a.window
      autoMitigate: a.autoMitigate
      muteActionsDuration: a.mute
      criteria: {
        allOf: [
          {
            query: a.query
            timeAggregation: 'Count'
            operator: 'GreaterThan'
            threshold: 0
            failingPeriods: {
              numberOfEvaluationPeriods: 1
              minFailingPeriodsToAlert: 1
            }
          }
        ]
      }
      actions: {
        actionGroups: [ actionGroup.id ]
      }
    }
  }
]
