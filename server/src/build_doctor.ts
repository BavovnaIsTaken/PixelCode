/**
 * Build Doctor — autonomous Flutter build-error fixer.
 *
 * On a failed flutter build, analyzes the log with Claude Haiku and applies
 * minimal file patches to fix the root cause, then signals the caller to
 * retry the build. Escalates to Sonnet after MAX_HAIKU_ITERATIONS failures.
 *
 * After a successful fix + retry build, publishBuildFix commits and pushes:
 *   - solo / feature branch with ≤2 contributors → push directly
 *   - protected branch or ≥3 contributors → new fix branch + push + gh pr create
 */

import {
  query,
  type SDKAssistantMessage,
} from "@anthropic-ai/claude-agent-sdk";
import { execFileSync } from "child_process";

const HAIKU_MODEL = "haiku" as const;
const SONNET_MODEL = "sonnet" as const;
const MAX_HAIKU_ITERATIONS = 2;

const SYSTEM_PROMPT = `You are an autonomous Flutter build-error doctor.
Your only job: read a failed flutter build log, identify the root cause, and apply the minimal fix directly to the source files.

Rules:
- Read files before editing them.
- Fix only what is needed — do not refactor unrelated code.
- If pubspec.yaml is changed, run: bash -c "flutter pub get" (using the Bash tool).
- Do NOT run flutter build — the caller will retry.
- After fixing, output a single concise line: "Fixed: <what you changed>".
- If the error is not fixable automatically (e.g. missing signing certificate, hardware issues), output: "CANNOT_FIX: <reason>".
- Never ask for confirmation. Act immediately.`;

export interface BuildDoctorResult {
  fixed: boolean;
  iterations: number;
  summary: string;
}

export async function runBuildDoctor(
  buildLog: string,
  projectCwd: string,
  onLog: (msg: string) => void,
): Promise<BuildDoctorResult> {
  const totalIterations = MAX_HAIKU_ITERATIONS + 1; // 2× haiku + 1× sonnet

  for (let i = 0; i < totalIterations; i++) {
    const isEscalation = i >= MAX_HAIKU_ITERATIONS;
    const model = isEscalation ? SONNET_MODEL : HAIKU_MODEL;
    const modelLabel = isEscalation ? "Sonnet" : "Haiku";
    const attempt = i + 1;

    onLog(`[AI Doctor] Аналізую помилку (спроба ${attempt}/${totalIterations}, ${modelLabel})...`);

    const prompt = `Flutter build failed. Analyze the errors and fix the root cause.

BUILD LOG:
\`\`\`
${buildLog.slice(-12000)}
\`\`\`

Apply the fix now.`;

    try {
      let fixSummary = "";

      const q = query({
        prompt,
        options: {
          systemPrompt: SYSTEM_PROMPT,
          model,
          allowedTools: ["Read", "Edit", "Write", "Glob", "Grep", "Bash"],
          cwd: projectCwd,
          permissionMode: "bypassPermissions",
          maxTurns: 20,
          persistSession: false,
        },
      });

      for await (const msg of q) {
        if (msg.type === "assistant") {
          const content = (msg as SDKAssistantMessage).message?.content;
          if (Array.isArray(content)) {
            for (const block of content) {
              if (block.type === "text" && block.text) {
                for (const line of block.text.split("\n")) {
                  const trimmed = line.trim();
                  if (trimmed) onLog(`[AI Doctor] ${trimmed}`);
                }
                fixSummary += block.text;
              }
            }
          }
        }
      }

      if (/CANNOT_FIX:/i.test(fixSummary)) {
        const reason = fixSummary.match(/CANNOT_FIX:\s*(.+)/i)?.[1]?.trim() ?? "невідома причина";
        onLog(`[AI Doctor] Не вдається виправити автоматично: ${reason}`);
        return { fixed: false, iterations: attempt, summary: reason };
      }

      const fixLine = fixSummary.match(/Fixed:\s*(.+)/i)?.[1]?.trim() ?? "зміни застосовано";
      onLog(`[AI Doctor] Готово: ${fixLine}`);
      return { fixed: true, iterations: attempt, summary: fixLine };

    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      onLog(`[AI Doctor] Помилка при виклику AI (спроба ${attempt}): ${errMsg}`);

      if (isEscalation) {
        return { fixed: false, iterations: attempt, summary: errMsg };
      }
      // continue to next iteration
    }
  }

  return { fixed: false, iterations: totalIterations, summary: "Вичерпано всі спроби" };
}

// ─── Git publish ────────────────────────────────────────────────────────────

const PROTECTED_BRANCHES = new Set(["main", "master", "develop", "dev"]);

function git(args: string[], cwd: string): string {
  return execFileSync("git", args, { cwd, encoding: "utf8" }).trim();
}

/**
 * After a successful fix + retry build: commit the doctor's changes and push.
 *
 * Decision logic:
 *   - protected branch (main/master/develop/dev) OR ≥3 recent contributors
 *     → new branch fix/build-doctor-<timestamp> + push + gh pr create
 *   - everything else → push directly to current branch
 */
export async function publishBuildFix(
  projectCwd: string,
  fixSummary: string,
  onLog: (msg: string) => void,
): Promise<void> {
  try {
    // Files touched by the doctor (modified tracked + new untracked)
    const modified = git(["diff", "--name-only", "HEAD"], projectCwd)
      .split("\n").filter(Boolean);
    const untracked = git(["ls-files", "--others", "--exclude-standard"], projectCwd)
      .split("\n").filter(Boolean);
    const toStage = [...new Set([...modified, ...untracked])];

    if (toStage.length === 0) {
      onLog("[Git] Build Doctor не змінив жодного файлу — нічого комітити.");
      return;
    }

    onLog(`[Git] Змінено: ${toStage.join(", ")}`);

    git(["add", "--", ...toStage], projectCwd);

    const currentBranch = git(["branch", "--show-current"], projectCwd);

    // Count unique commit authors in the last 2 weeks as proxy for team size
    let contributorCount = 1;
    try {
      const emails = git(["log", "--since=2.weeks", "--format=%ae"], projectCwd)
        .split("\n").filter(Boolean);
      contributorCount = new Set(emails).size || 1;
    } catch { /* fresh repo or no history */ }

    const commitMsg = [
      "fix(build): auto-fix flutter build error",
      "",
      fixSummary,
      "",
      "Co-Authored-By: Build Doctor <build-doctor@pixelcode.app>",
    ].join("\n");

    git(["commit", "-m", commitMsg], projectCwd);
    onLog(`[Git] Committed on ${currentBranch}`);

    const needsPR = PROTECTED_BRANCHES.has(currentBranch) || contributorCount >= 3;

    if (needsPR) {
      const stamp = new Date().toISOString().replace(/[T:.Z]/g, "-").slice(0, 19);
      const fixBranch = `fix/build-doctor-${stamp}`;

      git(["checkout", "-b", fixBranch], projectCwd);
      git(["push", "origin", fixBranch], projectCwd);
      onLog(`[Git] Запушено гілку ${fixBranch}`);

      try {
        execFileSync(
          "gh",
          [
            "pr", "create",
            "--title", "fix(build): auto-fix flutter build error",
            "--body", `## Auto-fix by Build Doctor\n\n${fixSummary}\n\n_Triggered by a failed flutter build._`,
            "--base", currentBranch,
          ],
          { cwd: projectCwd, encoding: "utf8" },
        );
        onLog(`[Git] PR відкрито: ${fixBranch} → ${currentBranch}`);
      } catch {
        onLog(`[Git] gh не знайдено або не авторизовано — гілку ${fixBranch} запушено, PR створіть вручну.`);
      }

      // Return to the original branch so the server stays in a clean state
      git(["checkout", currentBranch], projectCwd);
    } else {
      git(["push", "origin", currentBranch], projectCwd);
      onLog(`[Git] Запушено в ${currentBranch}`);
    }
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    onLog(`[Git] Помилка при публікації: ${msg}`);
  }
}
