// Lower backend. Secrets come from the workflow's environment (GitHub secrets), never from
// this file. IMAGE_TAG is the tag in manifests/image-tag.txt.
using './backend.bicep'

// Central US since 2026-11-20, beside the database (worktrac-source docs/architecture/region-move.md).
// A new name because the East US app keeps 'worktrac-backend-lower' until it is deleted.
param appName = 'worktrac-backend-lower-cus'
param location = 'centralus'
param managedEnvironmentName = 'worktrac-env-cus'
param image = 'ghcr.io/natestarner/worktrac-backend:${readEnvironmentVariable('IMAGE_TAG')}'

// 1 vCPU / 2Gi since 2026-10-30, for e2e throughput.
param cpu = '1'
param memory = '2Gi'

// Scales to zero when idle; one replica at most. (Ran at a fixed 2 for the Phase I multi-replica
// test window on 2026-11-02: full e2e, the barrage, and a deploy swapping both replicas, all green.)
param minReplicas = 0
param maxReplicas = 1
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

// Bound 2026-11-20 after api.dev's CNAME moved here: `az containerapp hostname add`, then
// `hostname bind --validation-method CNAME`, which issued this managed certificate (~7 min). The
// legacy worktrac-api-dev.starnerconsulting.co name is dropped: no shipped build or config ever
// called it.
param customDomains = [
  { name: 'api.dev.huddle.fitness', certificateName: 'mc-worktrac-env-c-api-dev-huddle-f-5278' }
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
  // Sign in with Apple and Google (worktrac-source docs/architecture/social-sign-in.md). Google's
  // ids are lower's web and iOS clients in Google Cloud project "Huddle"; not secrets. The Apple
  // private key is lower's own .p8 (Key ID below).
  { name: 'SOCIAL_SIGN_IN_ENABLED', value: 'true' }
  { name: 'SOCIAL_SIGN_IN_APPLE_CLIENT_IDS', value: 'fitness.huddle.app.lower,fitness.huddle.web.lower' }
  { name: 'SOCIAL_SIGN_IN_GOOGLE_CLIENT_IDS', value: '428334695403-r054kfu523mqkfj3lfatuttcfi7j770i.apps.googleusercontent.com,428334695403-m6cn7lk9h61hm92ltp6ul014cceoehbs.apps.googleusercontent.com' }
  { name: 'APPLE_TEAM_ID', value: 'R73HV8H48W' }
  { name: 'APPLE_SIGN_IN_KEY_ID', value: 'AQQA8YJY69' }
  { name: 'APPLE_SIGN_IN_PRIVATE_KEY', secret: true }
  // In-App Purchase (worktrac-source docs/in-app-purchase-plan.md). Huddle Lower is its own App
  // Store Connect app, so its bundle id, Apple ID and product prefix are lower's own. The issuer and
  // Key ID belong to the team-wide In-App Purchase key "Huddle server"; neither is a secret. The
  // private key is that key's .p8.
  { name: 'APPLE_IAP_BUNDLE_ID', value: 'fitness.huddle.app.lower' }
  { name: 'APPLE_IAP_APP_APPLE_ID', value: '6826555225' }
  { name: 'APPLE_IAP_ISSUER_ID', value: 'e1d9d530-bf88-4df8-8666-3f3e052555c5' }
  { name: 'APPLE_IAP_KEY_ID', value: 'N93N6MMUBY' }
  { name: 'APPLE_IAP_PRODUCT_PREFIX', value: 'huddle.lower.' }
  { name: 'APPLE_IAP_PRIVATE_KEY', secret: true }
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
  APPLE_SIGN_IN_PRIVATE_KEY: readEnvironmentVariable('APPLE_SIGN_IN_PRIVATE_KEY_LOWER')
  APPLE_IAP_PRIVATE_KEY: readEnvironmentVariable('APPLE_IAP_PRIVATE_KEY_LOWER')
}

param ghcrToken = readEnvironmentVariable('GHCR_TOKEN')
