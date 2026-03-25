// ============================================================================
// OpenBrain — Azure Infrastructure (Bicep)
// Deploys: PostgreSQL Flex + Container Apps + Azure OpenAI + Key Vault
// ============================================================================

targetScope = 'resourceGroup'

// ── Parameters ──────────────────────────────────────────────────────────────

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names (default: first 6 chars of resource group ID)')
param uniqueSuffix string = take(uniqueString(resourceGroup().id), 6)

@description('PostgreSQL administrator password')
@secure()
param dbPassword string

@description('MCP access key for OpenBrain API authentication')
@secure()
param mcpAccessKey string

@description('OpenBrain container image')
param containerImage string = 'ghcr.io/srnichols/openbrain:latest'

@description('PostgreSQL SKU name')
param postgresSku string = 'Standard_B1ms'

@description('PostgreSQL storage size in GB')
param postgresStorageGb int = 32

@description('Embedding vector dimensions (1536 for Azure OpenAI text-embedding-3-small)')
param embeddingDimensions int = 1536

// ── Variables ───────────────────────────────────────────────────────────────

var baseName = 'openbrain'
var pgServerName = '${baseName}-pg-${uniqueSuffix}'
var openaiName = '${baseName}-ai-${uniqueSuffix}'
var kvName = '${baseName}-kv-${uniqueSuffix}'
var caEnvName = '${baseName}-env-${uniqueSuffix}'
var caAppName = '${baseName}-api'
var logAnalyticsName = '${baseName}-logs-${uniqueSuffix}'
var dbName = 'openbrain'
var dbUser = 'openbrain'

// ── Log Analytics (required by Container Apps) ──────────────────────────────

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

// ── Azure OpenAI ────────────────────────────────────────────────────────────

resource openai 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: openaiName
  location: location
  kind: 'OpenAI'
  sku: { name: 'S0' }
  properties: {
    publicNetworkAccess: 'Enabled'
    customSubDomainName: openaiName
  }
}

resource embedDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: 'text-embedding-3-small'
  sku: {
    name: 'Standard'
    capacity: 120
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-3-small'
      version: '1'
    }
  }
}

resource llmDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openai
  name: 'gpt-4o-mini'
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
  }
  dependsOn: [embedDeployment]
}

// ── Key Vault ───────────────────────────────────────────────────────────────

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: kvName
  location: location
  properties: {
    sku: { name: 'standard', family: 'A' }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

resource secretDbPassword 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'db-password'
  properties: { value: dbPassword }
}

resource secretMcpKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'mcp-access-key'
  properties: { value: mcpAccessKey }
}

resource secretOpenAIKey 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'azure-openai-key'
  properties: { value: openai.listKeys().key1 }
}

// ── PostgreSQL Flexible Server ──────────────────────────────────────────────

resource pgServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: pgServerName
  location: location
  sku: {
    name: postgresSku
    tier: 'Burstable'
  }
  properties: {
    version: '17'
    administratorLogin: dbUser
    administratorLoginPassword: dbPassword
    storage: { storageSizeGB: postgresStorageGb }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: { mode: 'Disabled' }
  }
}

// Allow Azure services to connect (Container Apps)
resource pgFirewall 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pgServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

// Enable pgvector extension
resource pgVector 'Microsoft.DBforPostgreSQL/flexibleServers/configurations@2024-08-01' = {
  parent: pgServer
  name: 'azure.extensions'
  properties: {
    value: 'VECTOR'
    source: 'user-override'
  }
}

// Create the openbrain database
resource pgDatabase 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pgServer
  name: dbName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

// ── Container Apps Environment ──────────────────────────────────────────────

resource caEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: caEnvName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
}

// ── OpenBrain Container App ─────────────────────────────────────────────────

resource caApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: caAppName
  location: location
  properties: {
    managedEnvironmentId: caEnv.id
    configuration: {
      ingress: {
        external: true
        targetPort: 8080
        transport: 'http'
        allowInsecure: false
      }
      secrets: [
        { name: 'db-password', value: dbPassword }
        { name: 'mcp-access-key', value: mcpAccessKey }
        { name: 'azure-openai-key', value: openai.listKeys().key1 }
      ]
    }
    template: {
      containers: [
        {
          name: 'openbrain'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            { name: 'DB_HOST', value: pgServer.properties.fullyQualifiedDomainName }
            { name: 'DB_PORT', value: '5432' }
            { name: 'DB_NAME', value: dbName }
            { name: 'DB_USER', value: dbUser }
            { name: 'DB_PASSWORD', secretRef: 'db-password' }
            { name: 'DB_SSL', value: 'true' }
            { name: 'EMBEDDER_PROVIDER', value: 'azure-openai' }
            { name: 'EMBEDDING_DIMENSIONS', value: string(embeddingDimensions) }
            { name: 'AZURE_OPENAI_ENDPOINT', value: openai.properties.endpoint }
            { name: 'AZURE_OPENAI_KEY', secretRef: 'azure-openai-key' }
            { name: 'AZURE_OPENAI_EMBED_DEPLOYMENT', value: 'text-embedding-3-small' }
            { name: 'AZURE_OPENAI_LLM_DEPLOYMENT', value: 'gpt-4o-mini' }
            { name: 'MCP_ACCESS_KEY', secretRef: 'mcp-access-key' }
            { name: 'API_PORT', value: '8000' }
            { name: 'MCP_PORT', value: '8080' }
            { name: 'LOG_LEVEL', value: 'info' }
          ]
        }
      ]
      scale: {
        minReplicas: 0
        maxReplicas: 2
        rules: [
          {
            name: 'http-rule'
            http: { metadata: { concurrentRequests: '50' } }
          }
        ]
      }
    }
  }
  dependsOn: [pgDatabase, pgVector, pgFirewall, embedDeployment, llmDeployment]
}

// ── Outputs ─────────────────────────────────────────────────────────────────

@description('OpenBrain MCP SSE endpoint')
output mcpEndpoint string = 'https://${caApp.properties.configuration.ingress.fqdn}/sse'

@description('OpenBrain REST API endpoint')
output restEndpoint string = 'https://${caApp.properties.configuration.ingress.fqdn}'

@description('PostgreSQL server FQDN')
output pgHost string = pgServer.properties.fullyQualifiedDomainName

@description('Azure OpenAI endpoint')
output openaiEndpoint string = openai.properties.endpoint

@description('Key Vault name (for secret rotation)')
output keyVaultName string = keyVault.name
