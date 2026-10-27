# API Control Plane request conventions

Maintainer reference for the scripts. Agents operating the skill use the scripts, not raw requests.

## Base URL and tenant

`https://<subdomain>.backend.<region>.controlplane.boomi.com`, with no path prefix or version segment. Subdomain is the Boomi account ID lowercased with `_` replaced by `-`. Regions: `na`, `gb`.

Unauthenticated reads: `GET /serverInfo` (version), `GET /saasInfo` (tenant id, tier, `linkedWithBoomi`, `linkedWithCAM`), `GET /login/options` (which login methods the tenant allows). The OpenAPI document is served at `/v3/api-docs` and the Swagger UI at `/swagger-ui/index.html`.

## Authentication and scopes

Every other request carries `Authorization: Bearer <token>`. Two tokens work.

A Boomi Platform JWT from `GET https://api.boomi.com/auth/jwt/generate/<accountId>` with Basic auth `BOOMI_TOKEN.<username>:<apiToken>` and no `Accept` header (406 with one); the scripts obtain it through `acp_fetch_jwt`. It carries `iat` and `exp` five minutes apart, and an expired token answers 401. It resolves to the same control plane user and role as the portal login, so for a global administrator every scope in `GET /scopes` is authorized.

A Personal Access Token created in the admin portal or via `POST /accessTokens` with `{name, validityDays, scopes[]}` (0 days for no expiry); the value is returned once. Username and password login (`POST /login`) exists in the API but is disabled on Boomi-managed tenants.

Scopes follow the resource: `API_READ`, `API_WRITE`, `API_GATEWAY_READ`, `API_GATEWAY_WRITE`, `ENVIRONMENT_READ`, `ENVIRONMENT_WRITE`, `ORGANIZATION_READ`, `ORGANIZATION_WRITE`, `PLAN_READ`, `PLAN_WRITE`, `PLAN_ASSIGN_APIS`, `APPLICATION_READ`, `APPLICATION_WRITE`, `SUBSCRIPTIONS_READ`, `SUBSCRIPTIONS_WRITE`, `APPROVAL_REQUEST_READ`, `APPROVAL_REQUEST_WRITE`, `DISCOVERY`, `JOBS_READ`, `RULE_SETS_READ`, `RULE_SETS_WRITE`, `READ_GOVERNANCE_DATA`, `ACCESS_TENANT_DATA`, `CROSS_ORGANIZATION_ACCESS`. `GET /scopes` lists what the current user may grant.

The common library uses `ACP_TOKEN` when set and otherwise fetches a JWT per run, refreshing it after 240 s inside long polls. Both the platform credentials and the bearer reach curl through a config file on stdin (`-K -`) so they never appear in process arguments; stdin is therefore reserved and bodies go through `-d` or `--data-binary @file`.

## Paging, sorting, filtering

List endpoints take `page` (1-based, default 1), `size` (default 10; the scripts default to 50), and `sort` (`field,asc|desc`, repeatable). The envelope is:

```json
{"content": [], "size": 50, "number": 1, "last": true, "totalPages": 1, "totalElements": 0}
```

Most lists accept `text` for free-text search plus exact filters named after fields (`name`, `owner`, `status`, `environment`, `tags`, `deployed`). Relationship filters `candidatesForProduct`, `candidatesForApi`, `candidatesForParent`, `candidatesForChildren` return what may still be attached. `includeDeployedOn=true` expands deployment targets on APIs, products, and applications. `GET /subscriptions/{id}/accessPermissions`, `GET /ruleSets/{id}/ruleInfos`, `GET /jobs`, and `GET /boomi-jobs` return bare arrays rather than pages. `GET /approvalRequests/pending` returns a summary shape without the subscription id; `GET /approvalRequests` returns the full request.

## Identifiers

UUID strings. The API also accepts legacy integer IDs on the same parameters. API versions are addressed by version name, not ID. Platform types are addressed by UUID or by type key at `/platformType/byType/{type}`.

## Bodies and uploads

Create and update bodies are the full DTO; a well-formed read-only field is ignored, a malformed one fails deserialization with 400. Files (specifications, rule set files) upload as `multipart/form-data` with field `file`, with no explicit part content type needed for YAML or JSON; downloads return the raw file.

### API policy templates

Policy-template reads use these endpoints:

- `GET /apiPolicyTemplates` with optional `platformType`, `text`, and `apiDeploymentId` filters.
- `GET /apiPolicyTemplates/{id}` for detail.
- `GET /apiPolicyTemplates/{id}/usage` for API deployments currently assigned the template. The verified tenant returned a bare array from this endpoint even when paging parameters were accepted; do not assume every server returns the standard page envelope.
- `GET /apiPolicyTemplates/{id}/gatewayApiDeployments` for API deployments on the template's gateway.

The list and gateway-deployment reads return paged envelopes; the detail read returns one DTO. The verified tenant returned a bare array from `usage` even when paging parameters were accepted. A template DTO includes `id`, `name`, and `platformType`, with optional `version`, `sourceGatewayName`, `description`, and `metadata`. `metadata` is a JSON-encoded string. A deployment-filtered list identifies templates available on the deployment's gateway; inspect `apiDeploymentPolicies` on `GET /apis/{apiId}/deployments` for current assignments.

Assignments use `ApiDeploymentPolicyDTO`:

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

`POST /apis/{apiId}/deployments/{apiDeploymentId}/assignApiPolicyTemplate` accepts one DTO and its template list must contain exactly one reference; it adds the assignment without replacing existing paths. Its `/async` sibling returns `{"id":"<job-id>"}`. `POST /apis/{apiId}/deployments/{apiDeploymentId}/replaceApiPolicyTemplates` accepts an array of DTOs representing the complete desired assignment set; omitted paths are removed. Its `/async` sibling also returns a job ID. The verified synchronous assign and replace calls returned HTTP 200 with zero-byte bodies; scripts therefore use `finish` rather than parsing a response object. Async calls use the standard job polling behavior.

## Errors

Every error is the Spring Boot shape:

```json
{"timestamp": "…", "status": 401, "error": "Unauthorized", "message": "Invalid or expired bearer token!", "path": "/apis"}
```

Codes: 400 for a missing required field (`Tags is required.`, `Url must not be empty.`), a malformed value, or a business rule (organization mismatch on `add-api`, subscribing to a product with no production deployment, deploying an unapproved subscription); 401 for a bad or expired token; 404 for a deleted or unknown id (except organizations, which are soft-deleted and read back with status DELETED) and for accepted terms of use on a subscription that has none; 409 for a duplicate `name`, an API still in a product, or a lint already running; 500 with a not-supported-by-agent message when a gateway operation needs an agent that is not connected, and 500 for key regeneration on Cloud API Management (`Not yet implemented` synchronously, a null job parameter error on `/async`). A rejected `POST /environments` can leave its auto-created gateway behind.

## Asynchronous operations and jobs

Creates return 201 with the object; updates return 200; deletes, deploys, approvals, and discovery return 204 with no body. Deploy, delete, discovery, gateway refresh, key regeneration, and bulk lint have `/async` siblings that return `{"id": "<job-id>"}`.

Two job stores exist. `GET /jobs/{id}` returns `jobStatus` in SCHEDULED, ENQUEUED, PROCESSING, FAILED, SUCCEEDED, DELETED with `progressPercent` and message lists; discovery and deploy jobs land here. `GET /jobs` lists in-flight jobs only, so a finished job is reachable by id alone. `GET /boomi-jobs/{id}` returns `state` in AVAILABLE, SCHEDULED, RUNNING, RETRYABLE, COMPLETED, DISCARDED, CANCELLED with `errors[]`. `wait_for_job` in the common library reads the first and falls back to the second on 404.

`GET /runningJobs` is a third, entity-scoped tracker for the jobs that `lintUpdate` and `buildInIntegration` start; `jobType`, `entityId`, and `entityType` are all required query parameters (400 without `entityId`), lint jobs carry the specification id as `entityId` with `entityType` API_SPEC, and reading the entry consumes it.

Synchronous deploy calls block until the gateway work finishes; product, plan, and application deploys return at once when there is nothing to push.

## Specification sources

- Live: `<ACP_BASE_URL>/v3/api-docs`
- Published copy: `https://developer.boomi.com/APIs/controlPlaneOpenAPISpec.json`
- Reference pages: `https://developer.boomi.com/docs/APIs/ControlPlane/ControlPlane_overview` and `https://developer.boomi.com/docs/APIs/ControlPlane/api_control_plane_auth`
