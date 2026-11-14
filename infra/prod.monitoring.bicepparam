// Production alerts (infra/monitoring.bicep). Applied by deploy-prod.yml's deploy-monitoring-prod job.
using './monitoring.bicep'

param appName = 'worktrac-backend-prod'
param sqlServerName = 'worktrac-sql-server'
param sqlDatabaseName = 'worktrac-db-prod'

param actionGroupName = 'huddle-prod-alerts'
param actionGroupShortName = 'huddle-prod'

// The inbox Huddle's other operational notifications go to. Not ADMIN_EMAILS: that setting also
// decides who can sign in to the admin portal, so it stays separate.
param emailReceivers = [
  { name: 'huddle-ops', address: 'huddle@starner.co' }
]
