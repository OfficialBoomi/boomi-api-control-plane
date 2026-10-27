---
name: boomi-api-control-plane
description: >-
  Operates Boomi API Control Plane (ACP, formerly APIIDA): the federated, multi-gateway API management layer that registers gateways, discovers APIs, scores specifications, bundles APIs into products with plans, and manages applications, subscriptions, policy templates, and approvals across Boomi API Gateway, Cloud API Management, AWS, Azure, Apigee, Kong, Gravitee, WSO2, MuleSoft, and Layer7. Use when the user works with API Control Plane, ACP, APIIDA, API products, subscription approvals, gateway agents, API governance scores, or API policy templates (list, inspect, discover, assign, and replace; creation, editing, and deletion belong to boomi-api-gateway). Not for building or deploying API Service components on the Boomi API Gateway (boomi-api-gateway) or for Cloud API Management (CAM, formerly Mashery) directly (boomi-cloud-api-management).
---

# boomi-api-control-plane

## Scope

In: tenant and token checks; organizations; environments and gateways, including agent tokens; discovery; APIs, versions, and specifications with lint scores; API policy-template reads and API-deployment assignments; API products with API, plan, and organization assignment; plans; applications; subscriptions and their API keys; approval requests; governance dashboards and rule set reads; background jobs.

Out: building custom gateway agents with the Control Plane Agent SDK (may be mentioned, never operated). Developer Portal content, Open Proxy Specification deployment, Git integration, webhooks, tenant identity configuration, MCP bridge and registry. Boomi API Gateway runtime, API Service components, and plans on that gateway belong to `boomi-api-gateway`. Cloud API Management belongs to `boomi-cloud-api-management`. Building the backend process behind an API is `boomi-integration` territory.

## What API Control Plane is

API Control Plane is a SaaS control plane above many API gateways. It never proxies API traffic. It holds one registry of APIs across every connected gateway, discovers what already runs there, scores each specification against Spectral rule sets, and lets an organization bundle APIs into products with plans that consumers subscribe to through applications. Those plans, applications, and subscriptions are written back down to the gateways, so the gateway enforces the keys and limits that the control plane defines.

Each gateway is reached through an **agent**, a container that connects outbound to the control plane with a one-time token. Boomi API Gateway and Cloud API Management gateways in the same Boomi account need no agent: they appear as managed gateways with their environments discovered automatically.

## Credentials

The scripts authenticate with the Boomi Platform credentials the family already uses, read from the workspace `.env`. Never accept them as arguments or paste them into chat.

| Key | Value |
|---|---|
| `BOOMI_USERNAME`, `BOOMI_API_TOKEN`, `BOOMI_ACCOUNT_ID` | Boomi Platform user, API token, and account ID. Each script run exchanges them for a short-lived platform JWT that the control plane accepts as its bearer token. |
| `ACP_BASE_URL` | Optional. The tenant backend, `https://<subdomain>.backend.<region>.controlplane.boomi.com`. When unset it is derived from the account ID (lowercased, `_` replaced by `-`) on the `na` region. Tenants in another region, such as `gb`, set it explicitly. |
| `ACP_TOKEN` | Optional. A Personal Access Token created in the ACP admin portal under Account Settings. When set it replaces the platform JWT, for example to run with a narrower scope set. |

The platform JWT carries the user's role in full; for an API Control Plane Administrator that is every scope, reads and writes. It expires after five minutes and the common library refreshes it during long polls. Username and password login is disabled on Boomi-managed tenants. Run `acp-env-check.sh` first: it reports which credential is in use, the resolved base URL, the tenant, and the user's role.

## Object model

| Object | Purpose | Key fields |
|---|---|---|
| Organization | Owner of APIs, products, applications, and users. Forms a tree via `parent`. | `name`, `displayName`, `email`, `type` PUBLISHER / CONSUMER / BOTH |
| API Gateway | A connection to one gateway runtime. `SINGLE` gateways carry one environment; `MULTI` gateways carry many. | `platformType`, `name`, `agentType` STANDALONE / MANAGED, `agent` status |
| Environment | A stage on a gateway that APIs deploy to. Access to publish or subscribe can be public or restricted per organization. | `name`, `displayName`, `stage` DEVELOPMENT / PRODUCTION, `status`, `symbol`, `color`, `url`, `platformType` |
| API | One API, discovered from a gateway or created in the control plane. | `name`, `displayName`, `type` REST / GRAPHQL, `status` ACTIVE / INACTIVE, `tags`, `owner`, `platformType`, `deploymentStatus`, `globalApiId` |
| API Version | A version of an API, addressed by its `name` (for example `v1`). Holds one specification. | `name`, `displayName`, `status` CONCEPT through RETIRED |
| API Specification | The OpenAPI or GraphQL file for a version, with lint results. | `securityScore`, `qualityScore` (0 to 100), error and warning counts |
| API Policy Template | A reusable policy configuration discovered from a connected gateway and assigned to API-deployment paths. ACP reads templates and manages their deployment assignments; template creation and editing stay in the gateway. | `id`, `name`, `version`, `platformType`, `sourceGatewayName`, `description`, `metadata` |
| API Deployment Policy Assignment | A path-to-template association on an API deployment. | `path`, `apiPolicyTemplates[]` with `apiPolicyTemplateId`, `name`, `version` |
| Plan | A tenant-global quota and rate limit definition attached to products. | `displayName`, `quotaHits` (0 = unlimited), `quotaInterval`, `rateLimit` (0 = off), `rateInterval` |
| API Product | A bundle of APIs and plans that consumers subscribe to. | `name`, `displayName`, `visibility` PUBLIC / RESTRICTED, `published`, `allowSelfServiceSubscription`, `mcpStatus`, `tags`, `subscribableStatus` |
| Application | A consumer identity that holds subscriptions and receives API keys. | `displayName`, `status` ACTIVE / INACTIVE, `owner` |
| Subscription | One application, one product, one plan. | `application`, `apiProduct`, `plan`, `approvalStatus` PENDING / APPROVED / DECLINED, `deploymentStatus` |
| Access Permission | The per-environment credential a subscription yields: API key, or key and secret. | `apiKey`, `apiSecret`, `keyType`, per-API URLs |
| Approval Request | Raised when the tenant's approval policy requires review of a subscription. | `status`, `comment`, `subscription` |
| Rule Set | A Spectral rule set that scores specifications. Two defaults ship and cannot be deleted. | `name`, `enabled`, `defaultRuleSet` |

`platformType` keys are BOOMI (Boomi API Gateway), CAM (Cloud API Management), AWS, AZURE, APIGEE, KONG, GRAVITEE, WSO2, MULESOFT, LAYER7, and UNIVERSAL for APIs created in the control plane rather than discovered. Read the tenant's list with `acp-gateway.sh platform-types`.

`deploymentStatus` on APIs, products, plans, applications, and subscriptions is one of CREATED, DEPLOYMENT_REQUIRED, DEPLOYMENT_IN_PROGRESS, DEPLOYED, DEPLOYMENT_FAILED, DELETION_IN_PROGRESS, DELETION_FAILED. On a product, plan, or application it reports the last deploy job, not gateway presence; a product can read DEPLOYED while still not subscribable.

`subscribableStatus` on a product tells you why it cannot be subscribed yet: NO_APIS, NO_PLANS, NOT_DEPLOYED, NOT_DEPLOYED_IN_PRODUCTION, ENVIRONMENT_ACCESS_DENIED, or OK. It moves NO_APIS, then NO_PLANS, then NOT_DEPLOYED or OK as APIs and plans are attached.

A product may only contain APIs owned by the product's own organization. Discovered APIs are owned by the default organization, so a product for them is owned by the default organization too, or the API is re-owned first.

Read `references/concept_model.md` for relationships, the connection model, visibility rules, and lifecycle detail.

## Core workflows

**Orient.** `acp-env-check.sh`, then `acp-gateway.sh list`, `acp-environment.sh list`, `acp-org.sh list`. Managed Boomi gateways are already present when the tenant is linked to the Boomi account.

**Connect a non-Boomi gateway.** Create the environment with `acp-environment.sh create`; a `SINGLE` gateway is created with it and the response embeds that gateway's agent token, so treat the whole response as a secret. `acp-environment.sh agent-token <env-id>` issues a fresh token later. The user runs the agent container with the token following the gateway's connection guide in the help documentation; the agent status stays NOT_CONNECTED until the container connects. Check with `acp-environment.sh agent <env-id>` until it reports CONNECTED.

If the create is rejected, the gateway may already exist: check `acp-gateway.sh list --platformType <type>` and delete the orphan, or the next attempt fails with 409 on the gateway name.

For multi-environment gateways use `acp-gateway.sh create`, which returns the token once, then `acp-gateway.sh discover-environments <gateway-id>` after the agent is connected; before that it fails with 500 and a not-supported-by-agent message.

**Discover.** `acp-discovery.sh run` imports APIs, specifications, and (with components) applications and subscriptions from every connected environment. Add `--policy-templates` when discovering APIs from a connected Boomi API Gateway to request policy-template discovery. Then `acp-api.sh list --deployed true`. A warning that the specification could not be fetched means the gateway holds no OpenAPI document for that API; attach one with `acp-api.sh upload-version-spec <api-id> <version> <file>`. The discovery endpoint returns no body on success, so verify the resulting template reads separately.

**Inspect and assign API policy templates.** `acp-policy-template.sh list` reads discovered templates; use `get`, `usage`, and `gateway-deployments` for detail and relationships. `list --apiDeploymentId <deployment-id>` filters to templates available on that deployment's gateway, not necessarily templates already assigned there. Read `acp-api.sh deployments <api-id>` and inspect `apiDeploymentPolicies` for current path assignments. Use `acp-api.sh assign-policy-template` with one path-assignment object to add a template without replacing existing assignments. Use `acp-api.sh replace-policy-templates` with the complete desired array when replacing assignments. Both mutations accept `--async`; async calls return and optionally wait for a job, while synchronous success has an empty response body.

**Register an API and its specification.** `acp-api.sh create`, then `acp-api.sh upload-spec <api-id> <spec-file>`; the version is read from the specification's `info.version`. Linting starts on upload and finishes within seconds; until then `spec-info` shows `lintNumbers` null with a not-yet-validated message. Review with `acp-api.sh spec-info` and `acp-api.sh lint`; `acp-api.sh relint` re-runs the rule sets and returns 409 while a lint is already running. An API created this way has platformType UNIVERSAL and runs on no gateway, so it can be scored and productized but not subscribed; subscription needs an API that is deployed in a PRODUCTION environment, which in this skill's scope means a discovered one.

**Productize.** `acp-plan.sh create`, `acp-product.sh create` with `owner` set to the organization that owns the APIs, `acp-product.sh add-api`, `acp-product.sh add-plan`. For RESTRICTED products, `acp-product.sh allow-org`. Confirm with `acp-product.sh get` until `subscribableStatus` is OK. `acp-product.sh deploy` only re-pushes existing subscription deployments and reports nothing to deploy until a subscription exists.

**Consume.** `acp-application.sh create`, then `acp-subscription.sh create`; create fails with 400 unless the product's APIs are deployed in a PRODUCTION environment. The new subscription is DEPLOYMENT_REQUIRED. Without an approval policy it is APPROVED at once.

Under an approval policy it is PENDING and the create response still shows `approvalRequest` null; read the request ID back with `acp-subscription.sh get <sub-id>` or `acp-approval.sh list --status PENDING` (`acp-approval.sh pending` is a summary without the subscription link). Resolve with `acp-approval.sh approve <request-id>` or `acp-approval.sh decline <request-id> --comment <text>`; the comment is stored on the request. Approval does not deploy, and deploying a PENDING or DECLINED subscription returns 400. Then `acp-subscription.sh deploy <sub-id>`, which blocks until the gateway work completes and marks the application, plan, and product DEPLOYED as well.

**Keys.** `acp-subscription.sh keys <sub-id>` returns one entry per environment with the API key and secret at the top level and, under `apiDetails`, each API's endpoint URL and where the key goes (header, query parameter, or body). The output is a secret; do not paste it into notes or transcripts. `acp-subscription.sh regenerate-key` fails with 500 on Cloud API Management environments, synchronous or `--async`, and the key is unchanged.

**Govern.** `acp-governance.sh api-scores --category SECURITY`, `org-scores`, `rule-violations`, `shadow-apis`, `zombie-apis`. `api-scores --category` lists only APIs with findings in that category, so a clean category returns an empty page; `rule-violations` counts violations per rule. A shadow API is any API without a specification, including one just created in the control plane. Rule sets: `acp-governance.sh rulesets`; the two built-in rule sets have rules to list but no downloadable file.

Deploy sub-commands (`deploy` on product, plan, application, subscription) push to every environment where the object is required. The subscription is the unit that reaches the gateway; the other three only refresh deployments a subscription already created. They run synchronously by default; `--async` returns a job that the script polls, or `--no-wait` to return the job id and poll later with `acp-job.sh wait`.

**Delete.** An API that belongs to a product cannot be deleted, with or without `--undeploy`; `acp-product.sh remove-api` first. A product deletes with APIs and plans still attached. Deleting a subscription removes its approval request; deleting an environment removes its SINGLE gateway. Deletes are immediate and a deleted object then returns 404, except an organization, which is soft-deleted. `list` no longer shows it, but `get` still returns it with `status` DELETED and an `(inactive)` suffix on its `name` and `displayName`.

## Payload templates

Create and update bodies are the object's full representation. Send only writable fields: a well-formed read-only field such as `id` is silently ignored, a malformed value is rejected with 400. Pass either a JSON file path or an inline JSON string.

```json
{"name": "payments", "displayName": "Payments", "email": "payments@example.com", "type": "PUBLISHER"}
```
Organization. Optional: `description`, `parent`.

```json
{"name": "orders-api", "displayName": "Orders API", "status": "ACTIVE", "tags": ["orders"], "type": "REST"}
```
API. `tags` is required, an empty list is fine. Optional: `description`, `owner` (defaults to the default organization), `url`, `platformType` (defaults to UNIVERSAL). A duplicate `name` returns 409.

```json
{
  "path": "/v1/example",
  "apiPolicyTemplates": [
    {
      "apiPolicyTemplateId": "<template-id>",
      "name": "Rate Limit",
      "version": "1"
    }
  ]
}
```
Assign one policy template to an API-deployment path with `acp-api.sh assign-policy-template`. The `apiPolicyTemplates` array must contain exactly one template reference for the assign operation. For replacement, pass an array of these path-assignment objects to `acp-api.sh replace-policy-templates`; it is the complete desired assignment set, so omitted paths are removed. Use the template's returned `name` and `version`; templates must be compatible with the target gateway. The synchronous endpoints return HTTP 200 with no body. Async endpoints return a job ID and use the standard job polling behavior.

```json
{"displayName": "Gold", "quotaHits": 100000, "quotaInterval": "MONTH", "rateLimit": 50, "rateInterval": "SECOND"}
```
Plan. Optional: `description`.

```json
{"name": "orders", "displayName": "Orders", "visibility": "PUBLIC", "allowSelfServiceSubscription": true, "published": false, "mcpStatus": "DISABLED", "tags": []}
```
API product. Optional: `description`, `owner` (must match the owner of the APIs it will contain).

```json
{"displayName": "Mobile App", "status": "ACTIVE"}
```
Application. Optional: `description`, `owner` (defaults to the default organization), `oauthCallbackUrl`, `oauthScope`. Display names are not unique. Responses carry `aiAgentKey`, a secret used for MCP access.

```json
{"application": "<app-id>", "apiProduct": "<product-id>", "plan": "<plan-id>"}
```
Subscription. Optional: `environments` (list of environment IDs, honored on create only).

```json
{"name": "aws-prod", "displayName": "AWS Production", "url": "https://api.example.com", "symbol": "AP", "color": "#1f77b4", "status": "ACTIVE", "pinned": false, "stage": "PRODUCTION", "platformType": "AWS"}
```
Environment. `url` is required. Optional: `apiGatewayName` (defaults to `name`), `subscribeAccessMode`, `publishAccessMode`, `apiUrlStrategy`. Read valid `platformType` values with `acp-gateway.sh platform-types`.

## Listing and paging

Every `list` accepts `--page <n>` (1-based), `--size <n>` (default 50), `--sort <field,asc|desc>`, and the filters shown in its `--help`. Responses carry `content`, `number`, `totalPages`, `totalElements`, and `last`. A few reads return a bare array instead: subscription keys, rule set rules, and job lists. IDs are UUIDs.

## Working copies

Specifications pulled with `acp-api.sh pull-spec` land in `active-development/apis/<api-id>/<version>.spec`. Rule set files pulled with `acp-governance.sh ruleset-file` land in `active-development/rule_sets/<id>.yaml`. Everything else is small JSON that flows through arguments and output.

## Scripts inventory

Resolve `<skill-path>` once (the directory holding this file) and invoke scripts from the project workspace so `.env` resolves. Every script has `--help`.

| Script | Sub-commands |
|---|---|
| `acp-env-check.sh` | tenant, token, role, tier limits |
| `acp-org.sh` | list, get, default, create, update, delete, publish-environments, subscribe-environments |
| `acp-gateway.sh` | list, get, create, update, delete, agent-token, refresh, refresh-all, discover-environments, application-deployments, platform-types, platform-type |
| `acp-environment.sh` | list, get, create, update, delete, agent, agent-token, agent-delete, refresh, refresh-all, deployments, publish-orgs, subscribe-orgs, grant-publish, revoke-publish, grant-subscribe, revoke-subscribe |
| `acp-discovery.sh` | run |
| `acp-api.sh` | list, get, create, update, delete, deployments, assign-policy-template, replace-policy-templates, versions, version, create-version, update-version, delete-version, upload-spec, upload-version-spec, pull-spec, spec-info, lint, relint, delete-spec |
| `acp-policy-template.sh` | list, get, usage, gateway-deployments |
| `acp-product.sh` | list, get, create, update, delete, apis, add-api, remove-api, plans, add-plan, remove-plan, organizations, allow-org, revoke-org, subscribable-environments, subscriptions, deploy, deployments |
| `acp-plan.sh` | list, get, create, update, delete, deploy, deployments, products |
| `acp-application.sh` | list, get, create, update, delete, deploy, deployments, subscriptions |
| `acp-subscription.sh` | list, get, create, change-plan, delete, deploy, deployments, keys, key, regenerate-key, terms |
| `acp-approval.sh` | list, pending, get, approve, decline |
| `acp-governance.sh` | api-scores, org-scores, rule-violations, shadow-apis, zombie-apis, active-apis, active-subscriptions, api-subscriptions, application-subscriptions, product-subscriptions, rulesets, ruleset, ruleset-rules, ruleset-file |
| `acp-job.sh` | get, wait, list, boomi-jobs, running, running-job |

Always reach the API through these scripts. Do not hand-roll requests, URLs, or authorization headers.

## References

- `references/concept_model.md`. Use when: explaining how organizations, gateways, environments, APIs, policy templates, products, plans, applications, and subscriptions relate; the agent and managed-gateway connection model; visibility and approval rules; governance concepts.
- `references/api_convention.md`. Use when: extending or debugging the scripts; you need the request conventions, scopes, error shape, policy-template DTOs, or the job model.
- Boomi documentation. Use when: a question goes beyond this skill. The API Management help index is `https://help.boomi.com/md/docs/Atomsphere/API%20Management/llms.txt` (API Control Plane pages carry the `cp-` prefix; fetch a page as markdown by swapping `/docs/` for `/md/docs/` and appending `.md`). Developer documentation starts at `https://developer.boomi.com/docs/APIs/ControlPlane/ControlPlane_overview`.
