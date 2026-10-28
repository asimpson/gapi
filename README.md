# Pi issue worker

A reusable GitHub Actions workflow that asks Pi to handle a new issue when it receives the `pi` label. It reacts with 👀 **on the issue** before starting Pi, then either comments with Pi's answer or opens a PR containing its code changes. An issue body is not an issue comment; this workflow does not handle replies to existing issues.

## Install in another repository

1. Publish `.github/workflows/pi-issue-reusable.yml` in this repository and pin its **commit SHA** in the consuming repository. Copy [`examples/pi-issue-caller.yml`](examples/pi-issue-caller.yml) to the consumer's `.github/workflows/pi-issue.yml`, replacing `OWNER/REPO` and `REF`. If this workflow repository is private, enable access to it from the consuming repositories in Actions settings.
2. For the default API-key mode, set the consuming repository's Actions secret `OPENAI_API_KEY`. Create the `pi` issue label. In repository Actions settings, enable **Allow GitHub Actions to create and approve pull requests**.
3. Open an issue with the `pi` label, or apply the label to an existing issue. An already-labeled issue runs on creation; subsequent changes to other labels do not rerun it. Optionally select a different OpenAI model via the caller's `model` input.

The caller grants `contents: write`, `issues: write`, and `pull-requests: write`; GitHub restricts each job of the reusable workflow further. Pi runs in a separate job with a read-only `GITHUB_TOKEN` and checkout credentials disabled. Its OpenAI API key, or in subscription mode a short-lived access token, is available only to the Pi step; `PI_AUTH_JSON` and `PI_AUTH_JSON_UPDATE_TOKEN` are used only by the credential step before Pi starts. The worker installs Pi on Node 22, passes the issue body through a file (not shell interpolation), captures Pi's final answer, and emits a binary-safe Git patch of staged changes. A separate job applies the patch to a clean checkout before creating/updating `pi/issue-N` and linking the PR from the issue. If there is no patch, it posts the answer as an issue comment instead.

## Optional: ChatGPT subscription (private repositories only)

Pi's **Sign in with ChatGPT** uses OAuth credentials on the `openai` provider, not an OpenAI API key or the legacy `openai-codex` login. This workflow pins Pi `1.1.0`. Subscription mode is best-effort for unattended CI, not a permanent subscription API key.

OpenAI rotates the refresh token on every refresh and rejects one that has already been used. The workflow therefore needs a sign-in of its own that nothing else refreshes, plus a token that lets it save each rotated credential back to its repository secret:

1. Install the matching Pi version locally with `npm install --global --ignore-scripts @earendil-works/pi-coding-agent@1.1.0`.
2. Sign in from a throwaway Pi config directory, so the workflow gets its own sign-in instead of sharing the one in `~/.pi/agent`:

   ```bash
   export PI_CODING_AGENT_DIR="$(mktemp -d)"
   pi
   ```

   Run `/login openai`, choose **Sign in with ChatGPT** (not the API-key option), complete the browser sign-in, and quit Pi.
3. Save **only** the `openai` entry, unchanged, as the private consuming repository's Actions secret `PI_AUTH_JSON`, then delete the throwaway directory:

   ```bash
   jq '{openai}' "$PI_CODING_AGENT_DIR/auth.json" | gh secret set PI_AUTH_JSON --repo OWNER/REPO
   rm -rf "$PI_CODING_AGENT_DIR" && unset PI_CODING_AGENT_DIR
   ```

   The entry must have `type: "oauth"`, `access`, `refresh`, `expires`, `clientId`, and `scopes` including `chatgpt.tokens.use.direct`; the issued `clientId` is required for refresh. Don't copy the entry from your everyday `~/.pi/agent/auth.json`: when two Pi installs share a sign-in, whichever refreshes second fails with `invalid_grant`. Never commit or paste the credentials into an issue, logs, or a PR.
4. Create a fine-grained personal access token with access to only the consuming repository and the **Secrets** repository permission set to **Read and write**, and save it as that repository's Actions secret `PI_AUTH_JSON_UPDATE_TOKEN`. The built-in `GITHUB_TOKEN` cannot write secrets. When this token expires, runs that need a refresh fail without spending the stored refresh token; replace the token and re-run.
5. In your copy of `examples/pi-issue-caller.yml`, change the job's inputs and secrets to:

   ```yaml
   with:
     auth_mode: subscription
     subscription_model: gpt-6-sol # or an OpenAI model offered by your subscription
   secrets:
     PI_AUTH_JSON: ${{ secrets.PI_AUTH_JSON }}
     PI_AUTH_JSON_UPDATE_TOKEN: ${{ secrets.PI_AUTH_JSON_UPDATE_TOKEN }}
   ```

**How refresh works:** Before Pi starts, the workflow checks when the access token in `PI_AUTH_JSON` expires. If that is within 40 minutes, longer than the job can run, the workflow refreshes the credential itself and immediately saves the rotated value to `PI_AUTH_JSON`. It first checks that `PI_AUTH_JSON_UPDATE_TOKEN` can write the repository's secrets, so a missing or broken update token fails the run without spending the stored refresh token. Pi then receives only the access token. Without the refresh token, Pi never refreshes, so it cannot rotate the saved credential out from under later runs. Subscription-mode agent jobs are serialized per repository, so each starts with the latest saved credential.

**If refresh fails with `invalid_grant`:** the stored refresh token was already used or has expired, usually because another Pi install shares the sign-in or a rotated credential was not saved. Earlier versions of this workflow let Pi refresh during the run and could not save the result, so a credential they refreshed must be replaced. Repeat steps 2 and 3 to create a new dedicated sign-in, and update the consuming workflow's pinned commit SHA to a version with this refresh flow.

**Migrating from the `openai-codex` login:** Sign in again using `/login openai` and **Sign in with ChatGPT** as in steps 2 and 3, then replace `PI_AUTH_JSON` with the new `openai` entry. Do **not** rename an `openai-codex` entry to `openai`: the OAuth client and grant are different.

The workflow rejects subscription mode in public repositories. It validates the required credential fields and scope, writes only the `openai` access token to a private temporary Pi config directory, and selects `openai`. It unsets `OPENAI_API_KEY` in subscription mode, so it does not fall back to API-key billing. Service availability, subscription eligibility, usage limits, and terms may also change. API-key mode (`auth_mode: api-key`) remains the default and needs only `OPENAI_API_KEY`.

**Security:** Issue content, repository files, and Pi-generated changes are untrusted. Pi can run shell commands and read its API key or OpenAI access token during its step; a separate publishing job prevents it from directly using write credentials, but does not make the agent sandboxed. Private repositories do **not** protect credentials from a malicious issue or repository instruction. Only label issues you are willing to fund and process, and review PRs before merging. Withholding the refresh token keeps it out of Pi's files and environment, but Pi runs in the same job as the credential step, and code running in a job can recover any secret that job uses, including `PI_AUTH_JSON` and `PI_AUTH_JSON_UPDATE_TOKEN`. Scope `PI_AUTH_JSON_UPDATE_TOKEN` to the consuming repository's secrets only, because it can overwrite them. The publisher never runs the generated code, but a repository's other workflows might. Generated PRs created with `GITHUB_TOKEN` do not trigger most other workflows; use a reviewed GitHub App token if PR CI must run automatically. The workflow fails rather than posting partial results if the credential refresh, Pi, or patch application fails; inspect the Actions run in that case.
