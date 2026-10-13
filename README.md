# Pi issue worker

A reusable GitHub Actions workflow that asks Pi to handle a new issue when it receives the `pi` label. It reacts with 👀 **on the issue** before starting Pi, then either comments with Pi's answer or opens a PR containing its code changes. An issue body is not an issue comment; this workflow does not handle replies to existing issues.

## Install in another repository

1. Publish `.github/workflows/pi-issue-reusable.yml` in this repository and pin its **commit SHA** in the consuming repository. Copy [`examples/pi-issue-caller.yml`](examples/pi-issue-caller.yml) to the consumer's `.github/workflows/pi-issue.yml`, replacing `OWNER/REPO` and `REF`. If this workflow repository is private, enable access to it from the consuming repositories in Actions settings.
2. For the default API-key mode, set the consuming repository's Actions secret `OPENAI_API_KEY`. Create the `pi` issue label. In repository Actions settings, enable **Allow GitHub Actions to create and approve pull requests**.
3. Open an issue with the `pi` label, or apply the label to an existing issue. An already-labeled issue runs on creation; subsequent changes to other labels do not rerun it. Optionally select a different OpenAI model via the caller's `model` input.

The caller grants `contents: write`, `issues: write`, and `pull-requests: write`; GitHub restricts each job of the reusable workflow further. Pi runs in a separate job with a read-only `GITHUB_TOKEN` and checkout credentials disabled. Its OpenAI credential is available only to the credential restore/run steps, and the optional `PI_AUTH_JSON_UPDATE_TOKEN` is not passed to the Pi command. The worker installs Pi on Node 22, passes the issue body through a file (not shell interpolation), captures Pi's final answer, and emits a binary-safe Git patch of staged changes. A separate job applies the patch to a clean checkout before creating/updating `pi/issue-N` and linking the PR from the issue. If there is no patch, it posts the answer as an issue comment instead.

## Optional: ChatGPT subscription (private repositories only)

Pi's **Sign in with ChatGPT** uses OAuth credentials on the `openai` provider, not an OpenAI API key or the legacy `openai-codex` login. This workflow pins Pi `1.1.0`. Subscription mode is best-effort for unattended CI, not a permanent subscription API key:

1. Install the matching Pi version locally with `npm install --global --ignore-scripts @earendil-works/pi-coding-agent@1.1.0`. Start Pi, run `/login openai`, and choose **Sign in with ChatGPT**, not the API-key option. Complete the browser sign-in.
2. From your local `~/.pi/agent/auth.json` (or `$PI_CODING_AGENT_DIR/auth.json` if overridden), make a JSON object with **only** the `openai` top-level entry, leaving its value unchanged. It must have `type: "oauth"`, `access`, `refresh`, `expires`, `clientId`, and `scopes` including `chatgpt.tokens.use.direct`. Keep any additional fields too. The issued `clientId` is required for refresh; these credentials cannot be reconstructed from the old Codex login. Don't copy your entire `auth.json`. Save that JSON as the private consuming repository's Actions secret `PI_AUTH_JSON`. Never commit or paste the credentials into an issue, logs, or a PR.
3. In your copy of `examples/pi-issue-caller.yml`, change the job's inputs and secrets to:

   ```yaml
   with:
     auth_mode: subscription
     subscription_model: gpt-6-sol # or an OpenAI model offered by your subscription
   secrets:
     PI_AUTH_JSON: ${{ secrets.PI_AUTH_JSON }}
     # Optional: lets the reusable workflow persist rotated OAuth credentials.
     # PI_AUTH_JSON_UPDATE_TOKEN: ${{ secrets.PI_AUTH_JSON_UPDATE_TOKEN }}
   ```

**Migrating from the old workflow:** Sign in again using `/login openai` and **Sign in with ChatGPT**, then replace `PI_AUTH_JSON` with the new `openai` entry. Do **not** rename an `openai-codex` entry to `openai`: the OAuth client and grant are different. Update the consuming workflow's pinned commit SHA to the version containing this migration.

The workflow rejects subscription mode in public repositories. It validates the required credential fields and scope, restores only the `openai` credential to a private temporary Pi config directory, and selects `openai`. It unsets `OPENAI_API_KEY` in subscription mode, so it does not fall back to API-key billing. OAuth access tokens expire, and OpenAI can rotate refresh tokens. If the workflow refreshes credentials without saving the rotated value, later runs can fail with `invalid_grant`; concurrent runs or local sessions sharing that credential can also conflict. The reusable workflow serializes subscription-mode agent jobs per repository, warns when a refresh changed the local credential, and can update `PI_AUTH_JSON` automatically when you pass `PI_AUTH_JSON_UPDATE_TOKEN`.

`PI_AUTH_JSON_UPDATE_TOKEN` must be a GitHub token authorized to write Actions secrets in the private consuming repository, such as a fine-grained PAT or GitHub App token with repository Secrets write access; the built-in `GITHUB_TOKEN` is not sufficient. It is used only by the post-Pi credential persistence step, not passed to the Pi command. If you do not use automatic persistence, log in locally again and update `PI_AUTH_JSON` whenever rotation makes the secret stale. Service availability, subscription eligibility, usage limits, and terms may also change. API-key mode (`auth_mode: api-key`) remains the default and needs only `OPENAI_API_KEY`.

**Security:** Issue content, repository files, and Pi-generated changes are untrusted. Pi can run shell commands and read its API key or OAuth credentials during its step; a separate publishing job prevents it from directly using write credentials, but does not make the agent sandboxed. Private repositories do **not** protect credentials from a malicious issue or repository instruction. Only label issues you are willing to fund and process, and review PRs before merging. If you enable `PI_AUTH_JSON_UPDATE_TOKEN`, scope it only to the consuming repository's Actions secrets because it can overwrite `PI_AUTH_JSON`; because it is used later in the same runner job, only enable it for workflows where you accept the untrusted-code risk. The publisher never runs the generated code, but a repository's other workflows might. Generated PRs created with `GITHUB_TOKEN` do not trigger most other workflows; use a reviewed GitHub App token if PR CI must run automatically. The workflow fails rather than posting partial results if Pi, credential persistence, or patch application fails; inspect the Actions run in that case.
