// Production alerts (infra/monitoring.bicep). Applied by deploy-prod.yml's deploy-monitoring-prod job.
using './monitoring.bicep'

// The Central US app since 2026-11-20 (worktrac-source docs/architecture/region-move.md). The rules
// are named after it, so this creates a new set; the old app's rules are deleted with the old app.
param appName = 'worktrac-backend-prod-cus'
param sqlServerName = 'worktrac-sql-server'
param sqlDatabaseName = 'worktrac-db-prod'

param actionGroupName = 'huddle-prod-alerts'
param actionGroupShortName = 'huddle-prod'

// The inbox Huddle's other operational notifications go to. Not ADMIN_EMAILS: that setting also
// decides who can sign in to the admin portal, so it stays separate.
param emailReceivers = [
  { name: 'huddle-ops', address: 'huddle@starner.co' }
]
