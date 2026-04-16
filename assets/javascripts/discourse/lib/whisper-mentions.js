// Matches @username tokens in the composer body. Username charset mirrors
// Discourse's default: letters, numbers, underscore, dot, dash, up to 60 chars.
// The (?:^|[\s(]) prefix keeps us from matching email addresses like foo@bar.
export const MENTION_RE = /(?:^|[\s(])@([a-zA-Z0-9_.\-]{1,60})/g;

export function extractMentionedUsernames(reply) {
  if (!reply || typeof reply !== "string" || !reply.includes("@")) {
    return [];
  }
  const seen = new Set();
  const out = [];
  let match;
  MENTION_RE.lastIndex = 0;
  while ((match = MENTION_RE.exec(reply)) !== null) {
    const u = match[1];
    const key = u.toLowerCase();
    if (!seen.has(key)) {
      seen.add(key);
      out.push(u);
    }
  }
  return out;
}

export function pendingMentions(reply, alreadyArmedUsernames) {
  const mentioned = extractMentionedUsernames(reply);
  if (!mentioned.length) {
    return [];
  }
  const armed = new Set(
    (alreadyArmedUsernames || [])
      .filter((u) => typeof u === "string")
      .map((u) => u.toLowerCase())
  );
  return mentioned.filter((u) => !armed.has(u.toLowerCase()));
}
