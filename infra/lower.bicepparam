// Lower backend. Secrets come from the workflow's environment (GitHub secrets), never from
// this file. IMAGE_TAG is the tag in manifests/image-tag.txt.
using './backend.bicep'

param appName = 'worktrac-backend-lower'
param image = 'ghcr.io/natestarner/worktrac-backend:${readEnvironmentVariable('IMAGE_TAG')}'

// 1 vCPU / 2Gi since 2026-10-30, for e2e throughput.
param cpu = '1'
param memory = '2Gi'

// TEMPORARY (2026-11-02): fixed at two replicas for the Phase I multi-replica test window, so
// every request pattern crosses replicas. Revert to min 0 / max 1 (scale to zero) when it ends.
param minReplicas = 2
param maxReplicas = 2
// The app's own health groups (application.yml, management.endpoint.health.group), not a TCP
// check: readiness holds a replica out of rotation until it has warmed up and takes it out while
// it drains on shutdown. Neither group checks the database, so a DB outage keeps every replica
// answering honest 503s instead of restarting or de-routing them all (resilience.md, axis B).
//
// Liveness is deliberately slow to give up (6 x 10s): its endpoint shares Tomcat's threads with
// the API, so a load spike that delays it for half a minute must not restart a healthy replica.
param probes = [
  {
    type: 'Liveness'
    httpGet: { path: '/actuator/health/liveness', port: 8080 }
    initialDelaySeconds: 0
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 6
    successThreshold: 1
  }
  {
    type: 'Readiness'
    httpGet: { path: '/actuator/health/readiness', port: 8080 }
    initialDelaySeconds: 0
    periodSeconds: 3
    timeoutSeconds: 3
    failureThreshold: 5
    successThreshold: 1
  }
  {
    type: 'Startup'
    httpGet: { path: '/actuator/health/liveness', port: 8080 }
    initialDelaySeconds: 1
    periodSeconds: 1
    timeoutSeconds: 3
    failureThreshold: 240
    successThreshold: 1
  }
]

// Above Spring's 25s graceful drain, so a replica stopped by a deploy or a scale-in finishes its
// in-flight requests (and claims nothing new from the outbox) before it is killed.
param terminationGracePeriodSeconds = 30

param customDomains = [
  { name: 'api.dev.huddle.fitness', certificateName: 'mc-worktrac-env-api-dev-huddle-f-7336' }
  { name: 'worktrac-api-dev.starnerconsulting.co', certificateName: 'mc-worktrac-env-worktrac-api-dev-2523' }
]

param env = [
  { name: 'SPRING_DATASOURCE_URL', secret: true }
  { name: 'SPRING_PROFILES_ACTIVE', value: 'lower' }
  {
    name: 'CORS_ALLOWED_ORIGINS'
    value: 'https://black-flower-0c9bf9d0f.7.azurestaticapps.net,https://worktrac-dev.starnerconsulting.co,https://app.dev.huddle.fitness,capacitor://localhost'
  }
  { name: 'APP_JWT_SECRET', secret: true }
  { name: 'ACS_EMAIL_CONNECTION_STRING', secret: true }
  { name: 'ACS_EMAIL_SENDER_ADDRESS', value: 'DoNotReply@huddle.fitness' }
  { name: 'E2E_TEST_SUPPORT_KEY', secret: true }
  { name: 'APP_EMAIL_APP_URL', value: 'https://app.dev.huddle.fitness/app/log' }
  { name: 'ADMIN_EMAILS', value: 'nate+huddleadmin@starner.co' }
  { name: 'EMAIL_DELIVERY_WEBHOOK_KEY', secret: true }
  { name: 'STRIPE_SECRET_KEY', secret: true }
  { name: 'STRIPE_PUBLISHABLE_KEY', secret: true }
  { name: 'STRIPE_WEBHOOK_SECRET', secret: true }
  { name: 'STRIPE_PRICE_MONTHLY', secret: true }
  { name: 'STRIPE_PRICE_YEARLY', secret: true }
  { name: 'STRIPE_RETURN_URL', value: 'https://app.dev.huddle.fitness/app/billing' }
  { name: 'COMPED_EMAILS', secret: true }
  { name: 'STRIPE_PRICE_PRO_STARTER_MONTH', secret: true }
  { name: 'STRIPE_PRICE_PRO_STARTER_YEAR', secret: true }
  { name: 'STRIPE_PRICE_PRO_STUDIO_MONTH', secret: true }
  { name: 'STRIPE_PRICE_PRO_STUDIO_YEAR', secret: true }
  { name: 'STRIPE_PRICE_PRO_PRACTICE_MONTH', secret: true }
  { name: 'STRIPE_PRICE_PRO_PRACTICE_YEAR', secret: true }
  { name: 'STRIPE_PRICE_PRO_UNLIMITED_MONTH', secret: true }
  { name: 'STRIPE_PRICE_PRO_UNLIMITED_YEAR', secret: true }
  { name: 'NATIVE_APP_STORE_URL', value: 'https://apps.apple.com/us/app/huddle-workout-tracker/id6826555272' }
]

param secretEnv = {
  SPRING_DATASOURCE_URL: readEnvironmentVariable('SQL_CONNECTION_STRING_LOWER')
  APP_JWT_SECRET: readEnvironmentVariable('APP_JWT_SECRET_LOWER')
  ACS_EMAIL_CONNECTION_STRING: readEnvironmentVariable('ACS_EMAIL_CONNECTION_STRING_LOWER')
  E2E_TEST_SUPPORT_KEY: readEnvironmentVariable('E2E_TEST_SUPPORT_KEY_LOWER')
  EMAIL_DELIVERY_WEBHOOK_KEY: readEnvironmentVariable('EMAIL_DELIVERY_WEBHOOK_KEY_LOWER')
  STRIPE_SECRET_KEY: readEnvironmentVariable('STRIPE_SECRET_KEY_LOWER')
  STRIPE_PUBLISHABLE_KEY: readEnvironmentVariable('STRIPE_PUBLISHABLE_KEY_LOWER')
  STRIPE_WEBHOOK_SECRET: readEnvironmentVariable('STRIPE_WEBHOOK_SECRET_LOWER')
  STRIPE_PRICE_MONTHLY: readEnvironmentVariable('STRIPE_PRICE_MONTHLY_LOWER')
  STRIPE_PRICE_YEARLY: readEnvironmentVariable('STRIPE_PRICE_YEARLY_LOWER')
  COMPED_EMAILS: readEnvironmentVariable('COMPED_EMAILS')
  STRIPE_PRICE_PRO_STARTER_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_STARTER_MONTH_LOWER')
  STRIPE_PRICE_PRO_STARTER_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_STARTER_YEAR_LOWER')
  STRIPE_PRICE_PRO_STUDIO_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_STUDIO_MONTH_LOWER')
  STRIPE_PRICE_PRO_STUDIO_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_STUDIO_YEAR_LOWER')
  STRIPE_PRICE_PRO_PRACTICE_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_PRACTICE_MONTH_LOWER')
  STRIPE_PRICE_PRO_PRACTICE_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_PRACTICE_YEAR_LOWER')
  STRIPE_PRICE_PRO_UNLIMITED_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_UNLIMITED_MONTH_LOWER')
  STRIPE_PRICE_PRO_UNLIMITED_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_UNLIMITED_YEAR_LOWER')
}

param ghcrToken = readEnvironmentVariable('GHCR_TOKEN')
