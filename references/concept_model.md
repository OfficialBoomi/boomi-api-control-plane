# API Control Plane concept model

Contents
- Purpose and position
- Connection model: gateways, environments, agents
- Ownership and visibility: organizations
- Supply side: APIs, versions, specifications
- Packaging: plans and API products
- Demand side: applications, subscriptions, approvals, keys
- Deployment model
- Governance: rule sets, scores, findings
- Users and roles
- Related surfaces this skill does not operate

## Purpose and position

API Control Plane governs APIs that run on many gateways from one place. It is a management layer, not a runtime: it stores the registry, drives discovery and deployment through agents, and leaves traffic to the gateways. A tenant is one control plane instance per Boomi account, reached at `https://<subdomain>.backend.<region>.controlplane.boomi.com` with an admin portal on top and up to ten Boomi-hosted Developer Portals beside it.

Every feature in the admin portal is also available in the management API, which is what this skill's scripts wrap.

## Connection model: gateways, environments, agents

```
API Gateway (platformType, SINGLE | MULTI, agentType STANDALONE | MANAGED)
  └─ Agent (status, gateway status, capabilities)
  └─ Environment 1..n (stage DEVELOPMENT | PRODUCTION, url, publish/subscribe access)
```

**Platform types** name the gateway product: Boomi API Gateway, Boomi Cloud API Management, AWS API Gateway, Azure API Management, Apigee, Kong, Gravitee, WSO2, MuleSoft Anypoint, Broadcom Layer7, plus `UNIVERSAL` for APIs authored in the control plane from an Open Proxy Specification. Custom platform types come from the Agent SDK. Read the live list rather than assuming identifiers.

**API Gateway** is one connection to a runtime. A `SINGLE` gateway is created implicitly with its environment; a `MULTI` gateway is created first and its environments are then discovered from it.

**Environment** is what APIs, plans, applications, and subscriptions deploy to. Each has exactly one stage. A product can only be subscribed from a Developer Portal once its APIs are deployed to at least one PRODUCTION environment. Publish access and subscribe access are each PUBLIC or RESTRICTED; RESTRICTED mode takes an allow-list of organizations.

**Agent** is a container that opens an outbound connection to the control plane using an agent token and holds the gateway's own credentials. The token is shown when the gateway is created and can be reissued, which invalidates the previous one, but is never readable again. It performs discovery, component deployment, and status probes. Which of those a platform supports is its capability set, visible on the agent record. Agent status moves NOT_CONFIGURED, CONNECTING, CONNECTED, or NOT_CONNECTED. The gateway status seen through the agent is one of UNKNOWN, CONNECTED, UNREACHABLE, UNAUTHORIZED, GENERAL_ERROR, AGENT_ERROR, AGENT_OFFLINE.

**Managed gateways.** Boomi API Gateway and Cloud API Management gateways in the same Boomi account as the tenant need no agent. They appear with `agentType` MANAGED, their environments are discovered automatically, and they cannot be deleted from the control plane. An agent is required only for Boomi gateways that live in a different Boomi account.

## Ownership and visibility: organizations

Every API, API product, application, and user belongs to exactly one organization. Organizations form a tree through `parent`.

| Type | Can do |
|---|---|
| CONSUMER | Developer Portal only: create applications and subscribe. |
| PUBLISHER | Admin portal and Developer Portal: own APIs and products. Cannot create applications. Does not see other publishing organizations. |
| BOTH | No restrictions. |

A RESTRICTED product is visible to the organizations on its allow-list; visibility granted to a parent cascades to its children, while applications do not cascade. A default organization exists in every tenant and is the default owner for new resources.

## Supply side: APIs, versions, specifications

```
API (type REST | GRAPHQL, status ACTIVE | INACTIVE, owner, platformType, tags)
  └─ API Version (name, e.g. v1; status CONCEPT → DESIGN → DEVELOPMENT → STAGING → PRODUCTION → DEPRECATED → RETIRED)
       └─ API Specification (OpenAPI 2 or 3, GraphQL schema; securityScore, qualityScore)
  └─ API Deployment per environment (gateway id, URL, endpoints)
       └─ API Deployment Policy Assignment per path
            └─ API Policy Template reference (template id, name, version)
```

API policy templates are reusable policy configurations created and versioned in a compatible gateway. ACP discovers and reads them, and assigns their references to paths on API deployments; template creation and editing remain gateway operations. The deployment's `apiDeploymentPolicies` field is the source of current path assignments. A template list filtered by `apiDeploymentId` reports templates available on that deployment's gateway, which may include templates not currently assigned.

An API arrives one of two ways. **Discovery** imports it from a connected gateway with its versions and specifications; for a Boomi gateway the `globalApiId` is the API Service component ID. **Creation** registers it in the control plane first, after which a specification is uploaded. Uploading a specification to the API reads the version from the document and creates or overwrites that version; uploading to a named version targets that version directly.

An INACTIVE API cannot be subscribed and is hidden from the Developer Portal. An API that belongs to a product cannot be deleted until it is removed from every product. A version that is deployed cannot be deleted. Tags are free strings used for filtering in the admin portal and Developer Portal; the list is required on create and may be empty.

## Packaging: plans and API products

**Plan** is tenant-global: a quota (`quotaHits` per `quotaInterval`, 0 for unlimited) and a rate limit (`rateLimit` per `rateInterval`, 0 for off). The control plane converts intervals to the nearest interval the target platform supports; DAY and MONTH quotas and SECOND rates are supported everywhere.

**API Product** bundles APIs and offers plans. A product is subscribable only when `subscribableStatus` is OK; the other values name the blocker (NO_APIS, NO_PLANS, NOT_DEPLOYED, NOT_DEPLOYED_IN_PRODUCTION, ENVIRONMENT_ACCESS_DENIED). Flags:

- `published`: visible in Developer Portals mapped to the same organization.
- `visibility`: PUBLIC to all, or RESTRICTED to the organizations on its allow-list.
- `allowSelfServiceSubscription`: consumers may subscribe from the portal without an administrator.
- `mcpStatus`: ENABLED exposes the product's REST operations as tools through the MCP bridge.

`platformTypes` on a product is derived from the APIs it contains. A product only accepts APIs owned by its own organization; discovered APIs belong to the default organization. Equivalents on other platforms: Cloud API Management Package, MuleSoft has no equivalent.

## Demand side: applications, subscriptions, approvals, keys

```
Application (status ACTIVE | INACTIVE, owner)
  └─ Subscription (apiProduct + plan; approvalStatus PENDING | APPROVED | DECLINED; deploymentStatus)
       ├─ Approval Request (status, comment, created by, resolving organization)
       └─ Access Permission per environment (keyType API_KEY | API_KEY_AND_SECRET, apiKey, apiSecret, per-API URLs)
```

An **application** is the consumer identity. Setting it INACTIVE suspends all its subscriptions; deploying an inactive application disables them on the gateways. Equivalents: Cloud API Management Application, MuleSoft Client Application.

A **subscription** binds one application to one product under one plan. It can only be created once the product's APIs are deployed in a PRODUCTION environment. The application and the product may belong to different organizations. An application may hold only one plan per API across products. Changing the plan is the only update a subscription accepts. Equivalents: Cloud API Management Package Key, MuleSoft Contract.

**Approval** is a tenant policy set under Configuration, Approvals: approval required OFF, ALL, PUBLIC, or RESTRICTED, and automatic approval within the requester's own organization OFF, ADMINS ONLY, or ALL USERS. A PENDING subscription waits until an administrator approves or declines; a decline carries a comment stored on the request. Approval only changes the status; deployment is a separate step, and a PENDING or DECLINED subscription cannot be deployed. The request is deleted with its subscription.

The **access permission** is what the consumer actually uses: the API key (and secret for platforms that issue one) per environment, with the URL of each API in the product on that environment.

## Deployment model

`deploymentStatus` on APIs, products, plans, applications, and subscriptions is one of CREATED, DEPLOYMENT_REQUIRED, DEPLOYMENT_IN_PROGRESS, DEPLOYED, DEPLOYMENT_FAILED, DELETION_IN_PROGRESS, DELETION_FAILED.

A new subscription starts in DEPLOYMENT_REQUIRED. Deploying it pushes the subscription, its application, and its plan to every environment that holds the product's APIs, and marks the application, plan, and product DEPLOYED in the same step. Deploying a product, plan, or application on its own only refreshes deployments that a subscription already created and reports nothing to deploy otherwise. Per-environment deployment records carry the last successful and last failed task (DEPLOY, UNDEPLOY, DISCOVER) and a failure message. Deleting an object can remove it from the gateways as well, or from the control plane only; deleting a subscription removes its key from the gateway.

## Governance: rule sets, scores, findings

**Rule sets** are Spectral rule files. Two defaults ship, Spectral OpenAPI and Spectral OWASP; they can be disabled but not deleted, and at least one rule set is always enabled. Custom rules declare a category of security or quality. Rule sets can be scoped to publishing organizations or apply to all.

**Scores.** Each specification receives a security score and a quality score from 0 to 100, computed as 100 minus deductions per error and warning. Scores roll up per API and per organization.

**Findings.** Shadow APIs have no specification. Zombie APIs have had no subscription for 90 days. Rule violations rank the most-broken rules. Slowest APIs need raw metrics from the gateway.

## Users and roles

Boomi Platform roles grant access to the tenant: API Control Plane Administrator and API Control Plane User. Inside the tenant a user is USER (works within their own organization), ADMIN (also manages the organization's users and approvals), or GLOBAL_ADMIN (all organizations and the Configuration menu). Personal Access Tokens carry a subset of the scopes the user's role allows.

## Related surfaces this skill does not operate

- **Developer Portal**: the consumer-facing site where products are browsed and applications subscribe. Portals, pages, menus, and branding are configured in the admin portal.
- **Open Proxy Specification**: a vendor-neutral proxy definition that lets the control plane create the API on gateways that support it, rather than discovering it.
- **Git integration**: APIs and documentation sourced from a repository, one tag per version.
- **MCP bridge and registry**: exposes MCP-enabled products to AI agents and publishes server catalogs.
- **Agent SDK**: a Java SDK for building agents for gateways the product does not support natively, registered as custom platform types.
- **Webhooks**: outbound notifications on subscription create and delete.
