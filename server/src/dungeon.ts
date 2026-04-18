/**
 * Dungeon training system for PixelCode agents.
 *
 * Runs a real challenge task for an agent, then uses a haiku judge to score
 * the output (1-10). XP awarded = difficulty × score × 10.
 */

import { query, type SDKAssistantMessage, type SDKResultMessage } from "@anthropic-ai/claude-agent-sdk";
import { hardwareToModel, type GameStateData } from "./agents.js";

// ─── Challenge definitions ─────────────────────────────────────────────────

export interface DungeonChallenge {
  skillType: number; // 0-4 matching SkillType enum
  difficulty: 1 | 2 | 3;
  title: string;
  prompt: string; // sent to the agent
  judgeRubric: string; // criteria for the haiku judge
}

const challenges: DungeonChallenge[] = [
  // ─── Speed (0) ───────────────────────────────────────────────────────────
  {
    skillType: 0, difficulty: 1, title: "Reverse a String",
    prompt: "Write a JavaScript function that reverses a string. Keep your answer under 10 lines. Output only the function, no explanation.",
    judgeRubric: "The answer should: (1) correctly reverse a string, (2) be concise (ideally 1-3 lines), (3) work for edge cases like empty string.",
  },
  {
    skillType: 0, difficulty: 2, title: "Fibonacci Fast",
    prompt: "Write a TypeScript function `fib(n: number): number` that returns the nth Fibonacci number using iteration (not recursion). Must run in O(n) time. Output only the function.",
    judgeRubric: "The answer should: (1) use iteration not recursion, (2) handle n=0 and n=1 correctly, (3) be clearly written, (4) have correct TypeScript types.",
  },
  {
    skillType: 0, difficulty: 3, title: "Binary Search",
    prompt: "Implement a generic binary search function in TypeScript: `binarySearch<T>(arr: T[], target: T, compare: (a: T, b: T) => number): number`. Returns index or -1. Output only the function.",
    judgeRubric: "The answer should: (1) be a correct binary search implementation, (2) be generic with proper TypeScript types, (3) use the compare function correctly, (4) handle empty arrays, (5) be concise.",
  },

  // ─── Code Quality (1) ────────────────────────────────────────────────────
  {
    skillType: 1, difficulty: 1, title: "Refactor: Magic Numbers",
    prompt: `Refactor this code to remove magic numbers and improve readability:

\`\`\`javascript
function calculatePrice(qty) {
  if (qty > 100) return qty * 9.99 * 0.85;
  if (qty > 50) return qty * 9.99 * 0.90;
  return qty * 9.99;
}
\`\`\`

Output only the refactored code with a brief comment for each constant.`,
    judgeRubric: "The answer should: (1) extract named constants for 9.99, 100, 50, 0.85, 0.90, (2) be more readable than the original, (3) preserve the same logic.",
  },
  {
    skillType: 1, difficulty: 2, title: "Refactor: God Function",
    prompt: `Split this function into smaller, well-named functions:

\`\`\`typescript
async function processUserOrder(userId: string, items: {id: string, qty: number}[]) {
  const user = await db.users.findById(userId);
  if (!user) throw new Error("User not found");
  if (!user.active) throw new Error("User inactive");
  let total = 0;
  for (const item of items) {
    const product = await db.products.findById(item.id);
    if (!product) throw new Error(\`Product \${item.id} not found\`);
    if (product.stock < item.qty) throw new Error(\`Insufficient stock for \${item.id}\`);
    total += product.price * item.qty;
  }
  const order = await db.orders.create({ userId, items, total });
  await emailService.send(user.email, \`Order \${order.id} confirmed\`);
  return order;
}
\`\`\`

Output only the refactored code.`,
    judgeRubric: "The answer should: (1) extract validateUser(), calculateTotal() or similar helper functions, (2) keep each function focused on one concern, (3) preserve all original behavior, (4) be more readable.",
  },
  {
    skillType: 1, difficulty: 3, title: "Identify Code Smells",
    prompt: `List ALL code quality issues in this code and provide a corrected version:

\`\`\`typescript
class DataProcessor {
  data: any[] = [];
  flag = false;

  process(d: any) {
    for (let i = 0; i < this.data.length; i++) {
      if (this.data[i] == d) {
        this.flag = true;
        this.data.splice(i, 1);
        i--;
      }
    }
    if (this.flag == true) {
      console.log("found");
      this.flag = false;
    }
  }
}
\`\`\``,
    judgeRubric: "The answer should identify: (1) loose equality (==), (2) any types, (3) meaningless names (d, flag), (4) mutation during iteration, (5) side-effectful flag, (6) console.log in class. Fixed code should address all issues.",
  },

  // ─── Communication (2) ───────────────────────────────────────────────────
  {
    skillType: 2, difficulty: 1, title: "Explain to Non-Programmer",
    prompt: `Explain what this code does in 3-4 sentences for someone who doesn't know programming:

\`\`\`javascript
const result = [1,2,3,4,5].filter(n => n % 2 === 0).map(n => n * 2);
\`\`\``,
    judgeRubric: "The answer should: (1) avoid jargon or explain any terms used, (2) accurately describe what happens (filter even numbers, double them), (3) be 3-4 sentences max, (4) use a real-world analogy if possible.",
  },
  {
    skillType: 2, difficulty: 2, title: "Write a PR Description",
    prompt: `Write a clear pull request description for these changes:
- Added Redis caching to the getUserProfile() endpoint
- Cache TTL: 5 minutes
- Cache key: "user:{userId}"
- Falls back to database on cache miss
- Added unit tests for cache hit/miss scenarios

Write the PR title and description in standard format.`,
    judgeRubric: "The answer should: (1) have a clear, concise PR title, (2) summarize the change in 1-2 sentences, (3) mention the cache TTL and key format, (4) mention the fallback behavior, (5) mention tests, (6) be well-structured.",
  },
  {
    skillType: 2, difficulty: 3, title: "Architecture Decision Record",
    prompt: `Write a short Architecture Decision Record (ADR) for choosing PostgreSQL over MongoDB for a user analytics system that stores: user events, aggregated stats, and user profiles. The team already knows SQL. Max 200 words.`,
    judgeRubric: "The answer should: (1) state the decision clearly, (2) give context/problem, (3) list 2-3 reasons for the choice, (4) acknowledge trade-offs, (5) be under 200 words, (6) use ADR format (Context, Decision, Consequences or similar).",
  },

  // ─── Problem Solving (3) ─────────────────────────────────────────────────
  {
    skillType: 3, difficulty: 1, title: "Find the Bug",
    prompt: `Find and fix the bug in this code:

\`\`\`javascript
function sumArray(arr) {
  let sum = 0;
  for (let i = 0; i <= arr.length; i++) {
    sum += arr[i];
  }
  return sum;
}
\`\`\`

Explain what the bug is, then show the fixed code.`,
    judgeRubric: "The answer should: (1) correctly identify the off-by-one error (i <= arr.length should be i < arr.length), (2) explain why it's a bug (arr[arr.length] is undefined), (3) provide the fixed code.",
  },
  {
    skillType: 3, difficulty: 2, title: "Debug Async Race Condition",
    prompt: `Explain the bug and provide a fix:

\`\`\`javascript
let cache = {};

async function getUser(id) {
  if (cache[id]) return cache[id];
  const user = await fetchFromDB(id);
  cache[id] = user;
  return user;
}

// Called simultaneously: getUser('123'), getUser('123'), getUser('123')
\`\`\`

What problem occurs and how do you fix it?`,
    judgeRubric: "The answer should: (1) identify the race condition (3 simultaneous DB calls despite cache check), (2) explain that all 3 calls bypass the cache before any resolves, (3) provide a fix using a promise cache or similar pattern.",
  },
  {
    skillType: 3, difficulty: 3, title: "Performance Problem",
    prompt: `This function is called thousands of times per second and is causing performance issues. Analyze why and provide an optimized version:

\`\`\`typescript
function hasPermission(userId: string, action: string, roles: Role[]): boolean {
  const userRoles = roles.filter(r => r.userId === userId);
  return userRoles.some(r => r.permissions.includes(action));
}

interface Role { userId: string; permissions: string[]; }
\`\`\``,
    judgeRubric: "The answer should: (1) identify O(n×m) complexity per call, (2) note repeated linear search on roles array, (3) suggest pre-indexing roles by userId (Map/Record), (4) note that permissions.includes is O(m) and Set would be O(1), (5) provide optimized code.",
  },

  // ─── Specialization (4) ──────────────────────────────────────────────────
  {
    skillType: 4, difficulty: 1, title: "React Performance Patterns",
    prompt: "Name and briefly explain 3 React performance optimization techniques. For each: name, one sentence explanation, and a code example (2-3 lines).",
    judgeRubric: "The answer should: (1) name 3 legitimate React optimization techniques (e.g., useMemo, useCallback, React.memo, virtualization, lazy loading, etc.), (2) explain each correctly, (3) include brief code examples, (4) be accurate.",
  },
  {
    skillType: 4, difficulty: 2, title: "TypeScript Generics",
    prompt: `Write a TypeScript generic utility function \`groupBy<T>\` that groups an array by a key:

\`\`\`typescript
// Usage:
groupBy([{name: 'Alice', dept: 'Eng'}, {name: 'Bob', dept: 'Eng'}, {name: 'Carol', dept: 'HR'}], 'dept')
// → { Eng: [...], HR: [...] }
\`\`\`

Output only the function with proper TypeScript types.`,
    judgeRubric: "The answer should: (1) be properly generic (T extends object, K extends keyof T), (2) return Record<string, T[]> or similar, (3) correctly group items, (4) have no TypeScript errors, (5) be concise.",
  },
  {
    skillType: 4, difficulty: 3, title: "Design a Rate Limiter",
    prompt: "Design a token bucket rate limiter class in TypeScript. It should: limit to N requests per second, support per-user limits, handle bursts gracefully. Include the class with types and a brief explanation of the algorithm. Max 60 lines.",
    judgeRubric: "The answer should: (1) implement token bucket algorithm correctly, (2) support per-user tracking (Map), (3) handle token refill over time, (4) include proper TypeScript types, (5) explain the algorithm briefly, (6) be under 60 lines.",
  },
];

// ─── Challenge lookup ──────────────────────────────────────────────────────

export function getChallenge(skillType: number, difficulty: 1 | 2 | 3): DungeonChallenge {
  const match = challenges.find(c => c.skillType === skillType && c.difficulty === difficulty);
  if (!match) {
    // Fallback to difficulty 1 of the requested skill
    return challenges.find(c => c.skillType === skillType) ?? challenges[0];
  }
  return match;
}

// ─── Dungeon result ────────────────────────────────────────────────────────

export interface DungeonResult {
  agentId: string;
  skillType: number;
  xpEarned: number;
  score: number;
  feedback: string;
  passed: boolean;
}

// ─── Run dungeon ───────────────────────────────────────────────────────────

/**
 * Runs a dungeon training session for an agent:
 * 1. Sends the challenge to the agent (using its hardware-tier model)
 * 2. Evaluates the output with a haiku judge
 * 3. Returns XP earned and feedback
 */
export async function runDungeon(
  agentId: string,
  skillType: number,
  difficulty: 1 | 2 | 3,
  gameState: GameStateData | undefined,
  projectCwd: string,
): Promise<DungeonResult> {
  const challenge = getChallenge(skillType, difficulty);

  // Use hardware-tier model for the agent (NOT skill-capped — dungeon is training)
  const hwTier = gameState?.agentHardware[agentId] ?? 0;
  const agentModel = hardwareToModel(hwTier);

  // ── Step 1: Run the agent on the challenge ─────────────────────────────
  let agentOutput = "";

  const agentQuery = query({
    prompt: challenge.prompt,
    options: {
      systemPrompt: `You are an expert software engineer completing a training exercise.
Answer directly and concisely. Focus on correctness and quality.
Do not introduce yourself. Do not explain what you are about to do. Just answer.`,
      model: agentModel,
      allowedTools: [],
      cwd: projectCwd,
      includePartialMessages: false,
      permissionMode: "acceptEdits",
      maxTurns: 3,
      persistSession: false,
    },
  });

  for await (const msg of agentQuery) {
    if (msg.type === "assistant") {
      const asst = msg as SDKAssistantMessage;
      if (!asst.parent_tool_use_id) {
        for (const block of asst.message.content) {
          if (block.type === "text") {
            agentOutput += (block as { type: "text"; text: string }).text;
          }
        }
      }
    }
    if (msg.type === "result") {
      const res = msg as SDKResultMessage;
      const resText = "result" in res ? (res as unknown as Record<string, string>).result ?? "" : "";
      if (resText && !agentOutput) agentOutput = resText;
    }
  }

  if (!agentOutput.trim()) {
    return { agentId, skillType, xpEarned: 0, score: 0, feedback: "Agent produced no output.", passed: false };
  }

  // ── Step 2: Judge with haiku ───────────────────────────────────────────
  const judgePrompt = `You are a strict but fair code quality judge. Evaluate the following response to a training challenge.

CHALLENGE:
${challenge.prompt}

AGENT'S RESPONSE:
${agentOutput}

EVALUATION CRITERIA:
${challenge.judgeRubric}

Score the response from 1 to 10:
- 1-3: Wrong, incomplete, or very poor quality
- 4-6: Partially correct or acceptable but with notable issues
- 7-8: Good — correct and mostly meets criteria
- 9-10: Excellent — fully correct, meets all criteria, well-written

Respond in this EXACT format (no other text):
SCORE: <number 1-10>
FEEDBACK: <one or two sentences explaining the score>`;

  let judgeOutput = "";

  const judgeQuery = query({
    prompt: judgePrompt,
    options: {
      systemPrompt: "You are a precise code evaluator. Always respond in the exact requested format.",
      model: "haiku",
      allowedTools: [],
      cwd: projectCwd,
      includePartialMessages: false,
      permissionMode: "acceptEdits",
      maxTurns: 1,
      persistSession: false,
    },
  });

  for await (const msg of judgeQuery) {
    if (msg.type === "assistant") {
      const asst = msg as SDKAssistantMessage;
      if (!asst.parent_tool_use_id) {
        for (const block of asst.message.content) {
          if (block.type === "text") {
            judgeOutput += (block as { type: "text"; text: string }).text;
          }
        }
      }
    }
    if (msg.type === "result") {
      const res = msg as SDKResultMessage;
      const resText = "result" in res ? (res as unknown as Record<string, string>).result ?? "" : "";
      if (resText && !judgeOutput) judgeOutput = resText;
    }
  }

  // ── Step 3: Parse judge output ─────────────────────────────────────────
  const scoreMatch = judgeOutput.match(/SCORE:\s*(\d+)/i);
  const feedbackMatch = judgeOutput.match(/FEEDBACK:\s*(.+)/i);

  const score = scoreMatch ? Math.min(10, Math.max(1, parseInt(scoreMatch[1], 10))) : 5;
  const feedback = feedbackMatch ? feedbackMatch[1].trim() : "Challenge completed.";
  const xpEarned = difficulty * score * 10;
  const passed = score >= 5;

  return { agentId, skillType, xpEarned, score, feedback, passed };
}
