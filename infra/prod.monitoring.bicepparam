// Production alerts (infra/monitoring.bicep). Applied by deploy-prod.yml's deploy-monitoring-prod job.
using './monitoring.bicep'

param appName = 'worktrac-backend-prod'
param sqlServerName = 'worktrac-sql-server'
param sqlDatabaseName = 'worktrac-db-prod'

param actionGroupName = 'huddle-prod-alerts'
param actionGroupShortName = 'huddle-prod'

// The same admin address the app's own alerts go to (ADMIN_EMAILS in prod.bicepparam).
param emailReceivers = [
  { name: 'huddle-admin', address: 'nate+huddleadmin@starner.co' }
]
