// Production backend. Secrets come from the workflow's environment (GitHub secrets), never
// from this file. IMAGE_TAG is the tag in the `production` branch's manifests/image-tag.txt.
using './backend.bicep'

param appName = 'worktrac-backend-prod'
param image = 'ghcr.io/natestarner/worktrac-backend:${readEnvironmentVariable('IMAGE_TAG')}'

// Deliberately small for now: scale up (vertically) first, then out, as usage grows.
param cpu = '0.25'
param memory = '0.5Gi'

// Always warm.
param minReplicas = 1
param maxReplicas = 1

// The app's own health groups, as on lower (see lower.bicepparam for why: neither group checks the
// database, so a DB outage keeps the replica answering honest 503s instead of restarting it).
// Until 2026-11-19 production had none, so the platform's default TCP checks applied, and they
// restart after ~30s without an answer: five liveness kills in 30 days (Oct 22 - Nov 19), each a
// ~4-minute outage on this one small replica while it restarted.
//
// Liveness is lower's: 6 x 10s, so a stall of up to a minute is survived, not restarted.
// Readiness is MORE tolerant than lower's (6 x 5s here, 5 x 3s there): this is the only replica,
// so taking it out of rotation is an outage, not a reroute.
// Startup allows 240s: a restart at 0.25 vCPU took ~2.5 minutes on 2026-11-19 (a deploy, ~20s).
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
    periodSeconds: 5
    timeoutSeconds: 5
    failureThreshold: 6
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

param scaleRules = [
  {
    name: 'http-scaler'
    http: {
      metadata: {
        concurrentRequests: '10'
      }
    }
  }
]

param customDomains = [
  { name: 'api.huddle.fitness', certificateName: 'mc-worktrac-env-api-huddle-fitne-5059' }
  { name: 'worktrac-api.starnerconsulting.co', certificateName: 'mc-worktrac-env-worktrac-api-sta-8281' }
]

param env = [
  { name: 'SPRING_DATASOURCE_URL', secret: true }
  { name: 'SPRING_PROFILES_ACTIVE', value: 'production' }
  {
    name: 'CORS_ALLOWED_ORIGINS'
    value: 'https://black-desert-00fee190f.7.azurestaticapps.net,https://worktrac-app.starnerconsulting.co,https://app.huddle.fitness,capacitor://localhost'
  }
  { name: 'APP_JWT_SECRET', secret: true }
  { name: 'ACS_EMAIL_CONNECTION_STRING', secret: true }
  { name: 'ACS_EMAIL_SENDER_ADDRESS', value: 'DoNotReply@huddle.fitness' }
  { name: 'APP_EMAIL_APP_URL', value: 'https://app.huddle.fitness/app/log' }
  { name: 'ADMIN_EMAILS', value: 'nate+huddleadmin@starner.co' }
  { name: 'EMAIL_DELIVERY_WEBHOOK_KEY', secret: true }
  { name: 'STRIPE_SECRET_KEY', secret: true }
  { name: 'STRIPE_PUBLISHABLE_KEY', secret: true }
  { name: 'STRIPE_WEBHOOK_SECRET', secret: true }
  { name: 'STRIPE_PRICE_MONTHLY', secret: true }
  { name: 'STRIPE_PRICE_YEARLY', secret: true }
  { name: 'STRIPE_RETURN_URL', value: 'https://app.huddle.fitness/app/billing' }
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
  // ids are production's web and iOS clients in Google Cloud project "Huddle"; not secrets. The
  // Apple private key is production's own .p8 (Key ID below).
  { name: 'SOCIAL_SIGN_IN_ENABLED', value: 'true' }
  { name: 'SOCIAL_SIGN_IN_APPLE_CLIENT_IDS', value: 'fitness.huddle.app,fitness.huddle.web' }
  { name: 'SOCIAL_SIGN_IN_GOOGLE_CLIENT_IDS', value: '428334695403-brvpo8hso2k60qf4jaqqdfhlg36e67dh.apps.googleusercontent.com,428334695403-4rvt9vdifhuoqv681gufes3qses28j20.apps.googleusercontent.com' }
  { name: 'APPLE_TEAM_ID', value: 'R73HV8H48W' }
  { name: 'APPLE_SIGN_IN_KEY_ID', value: '38GWY77F9V' }
  { name: 'APPLE_SIGN_IN_PRIVATE_KEY', secret: true }
  // In-App Purchase (worktrac-source docs/in-app-purchase-plan.md). Huddle's own App Store Connect
  // app: its bundle id, Apple ID and the production product prefix. The issuer and Key ID belong to
  // the team-wide In-App Purchase key "Huddle server" (the same key lower uses); neither is a
  // secret. The private key is that key's .p8.
  { name: 'APPLE_IAP_BUNDLE_ID', value: 'fitness.huddle.app' }
  { name: 'APPLE_IAP_APP_APPLE_ID', value: '6826555272' }
  { name: 'APPLE_IAP_ISSUER_ID', value: 'e1d9d530-bf88-4df8-8666-3f3e052555c5' }
  { name: 'APPLE_IAP_KEY_ID', value: 'N93N6MMUBY' }
  { name: 'APPLE_IAP_PRODUCT_PREFIX', value: 'huddle.' }
  { name: 'APPLE_IAP_PRIVATE_KEY', secret: true }
]

param secretEnv = {
  SPRING_DATASOURCE_URL: readEnvironmentVariable('SQL_CONNECTION_STRING_PROD')
  APP_JWT_SECRET: readEnvironmentVariable('APP_JWT_SECRET_PROD')
  ACS_EMAIL_CONNECTION_STRING: readEnvironmentVariable('ACS_EMAIL_CONNECTION_STRING_PROD')
  EMAIL_DELIVERY_WEBHOOK_KEY: readEnvironmentVariable('EMAIL_DELIVERY_WEBHOOK_KEY_PROD')
  STRIPE_SECRET_KEY: readEnvironmentVariable('STRIPE_SECRET_KEY_PROD')
  STRIPE_PUBLISHABLE_KEY: readEnvironmentVariable('STRIPE_PUBLISHABLE_KEY_PROD')
  STRIPE_WEBHOOK_SECRET: readEnvironmentVariable('STRIPE_WEBHOOK_SECRET_PROD')
  STRIPE_PRICE_MONTHLY: readEnvironmentVariable('STRIPE_PRICE_MONTHLY_PROD')
  STRIPE_PRICE_YEARLY: readEnvironmentVariable('STRIPE_PRICE_YEARLY_PROD')
  COMPED_EMAILS: readEnvironmentVariable('COMPED_EMAILS')
  STRIPE_PRICE_PRO_STARTER_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_STARTER_MONTH_PROD')
  STRIPE_PRICE_PRO_STARTER_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_STARTER_YEAR_PROD')
  STRIPE_PRICE_PRO_STUDIO_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_STUDIO_MONTH_PROD')
  STRIPE_PRICE_PRO_STUDIO_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_STUDIO_YEAR_PROD')
  STRIPE_PRICE_PRO_PRACTICE_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_PRACTICE_MONTH_PROD')
  STRIPE_PRICE_PRO_PRACTICE_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_PRACTICE_YEAR_PROD')
  STRIPE_PRICE_PRO_UNLIMITED_MONTH: readEnvironmentVariable('STRIPE_PRICE_PRO_UNLIMITED_MONTH_PROD')
  STRIPE_PRICE_PRO_UNLIMITED_YEAR: readEnvironmentVariable('STRIPE_PRICE_PRO_UNLIMITED_YEAR_PROD')
  APPLE_SIGN_IN_PRIVATE_KEY: readEnvironmentVariable('APPLE_SIGN_IN_PRIVATE_KEY_PROD')
  APPLE_IAP_PRIVATE_KEY: readEnvironmentVariable('APPLE_IAP_PRIVATE_KEY_PROD')
}

param ghcrToken = readEnvironmentVariable('GHCR_TOKEN')
