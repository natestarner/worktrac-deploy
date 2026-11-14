// One backend Container App (lower or prod). Each environment's settings live in its
// .bicepparam file; this template is the shape they share.
//
// Azure replaces the whole `template` block on every apply, so anything left out here is
// REMOVED from the live app -- env vars, probes, scale rules. That's why every env var is
// listed explicitly, in the same order the live app has them (what-if compares arrays by
// position, so a reordering would show as a change).

@description('Container App name, e.g. worktrac-backend-lower.')
param appName string

param location string = 'eastus'

@description('The shared Container Apps environment both backends run in.')
param managedEnvironmentName string = 'worktrac-env'

@description('Full image reference, e.g. ghcr.io/natestarner/worktrac-backend:90ebc8f.')
param image string

@description('vCPU as a string, because Bicep has no decimal literals ("0.25", "1").')
param cpu string

param memory string

param minReplicas int
param maxReplicas int

@description('KEDA scale rules, or [] for none.')
param scaleRules array = []

@description('Container probes, or [] to leave the platform default.')
param probes array = []

@description('''Seconds a stopping replica gets to finish in-flight work before it is killed, or null to
leave the platform default. Spring's own drain is 25s (spring.lifecycle.timeout-per-shutdown-phase),
so this must stay above it.''')
param terminationGracePeriodSeconds int?

@description('Custom hostnames bound to this app: [{ name, certificateName }].')
param customDomains array = []

@description('''Env vars in order. Each is { name, value } for plain config or { name, secret: true }
for a value taken from secretEnv.''')
param env array

@secure()
@description('Secret env var values by name. Supplied from GitHub secrets at deploy time.')
param secretEnv object

@secure()
@description('GHCR token the app uses to pull its image.')
param ghcrToken string

param ghcrUsername string = 'natestarner'

resource managedEnvironment 'Microsoft.App/managedEnvironments@2025-07-01' existing = {
  name: managedEnvironmentName
}

var registrySecretName = 'ghcrio-natestarner'

// Secret env vars are stored as Container App secrets and the env var only names one
// (`secretRef`), so their values never appear in the app's template: not in the portal, not in
// `az containerapp show`, not to anyone with Reader. The app sees exactly the same environment.
//
// Secret names must be lowercase letters, digits and '-': SPRING_DATASOURCE_URL becomes
// spring-datasource-url.
var secretEnvVars = filter(env, e => e.?secret ?? false)

func secretName(envName string) string => toLower(replace(envName, '_', '-'))

// Changing only a secret's value does NOT start a new revision (secrets live on the app, not
// the revision), so a rotated secret would sit unused until something else changed. This short
// hash of every secret value changes whenever any of them does, and it is a plain env var, so it
// is part of the template and forces the new revision. A one-way 13-character hash of all the
// values together; it reveals nothing about any one of them.
var secretsFingerprint = uniqueString(string(secretEnv))

resource app 'Microsoft.App/containerApps@2025-07-01' = {
  name: appName
  location: location
  properties: {
    environmentId: managedEnvironment.id
    managedEnvironmentId: managedEnvironment.id
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      maxInactiveRevisions: 100
      ingress: {
        external: true
        targetPort: 8080
        exposedPort: 0
        transport: 'Auto'
        allowInsecure: false
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
        customDomains: [
          for domain in customDomains: {
            name: domain.name
            bindingType: 'SniEnabled'
            certificateId: '${managedEnvironment.id}/managedCertificates/${domain.certificateName}'
          }
        ]
      }
      registries: [
        {
          server: 'ghcr.io'
          username: ghcrUsername
          passwordSecretRef: registrySecretName
        }
      ]
      secrets: concat(
        [
          {
            name: registrySecretName
            value: ghcrToken
          }
        ],
        map(secretEnvVars, e => {
          name: secretName(e.name)
          value: secretEnv[e.name]
        })
      )
    }
    template: {
      terminationGracePeriodSeconds: terminationGracePeriodSeconds
      containers: [
        {
          name: appName
          image: image
          // Kept at the END so adding it leaves every existing env var at its position (what-if
          // compares arrays by position).
          env: concat(
            map(env, e => (e.?secret ?? false) ? { name: e.name, secretRef: secretName(e.name) } : { name: e.name, value: e.value }),
            [ { name: 'SECRETS_FINGERPRINT', value: secretsFingerprint } ]
          )
          resources: {
            cpu: json(cpu)
            memory: memory
          }
          probes: empty(probes) ? null : probes
        }
      ]
      scale: {
        minReplicas: minReplicas
        maxReplicas: maxReplicas
        cooldownPeriod: 300
        pollingInterval: 30
        rules: empty(scaleRules) ? null : scaleRules
      }
    }
  }
}
