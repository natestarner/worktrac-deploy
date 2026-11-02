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
      secrets: [
        {
          name: registrySecretName
          value: ghcrToken
        }
      ]
    }
    template: {
      terminationGracePeriodSeconds: terminationGracePeriodSeconds
      containers: [
        {
          name: appName
          image: image
          env: [
            for e in env: {
              name: e.name
              value: (e.?secret ?? false) ? secretEnv[e.name] : e.value
            }
          ]
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
