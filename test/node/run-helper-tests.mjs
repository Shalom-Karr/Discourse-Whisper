// Node runnable sanity tests for the pure-JS helpers. The same edge cases
// are mirrored (with richer QUnit syntax) in test/javascripts/unit/*.js for
// the Discourse Ember/QUnit test runner. This file lets the helpers be
// exercised without a browser — useful in CI environments that don't
// provide Chrome.
//
// Run with: `node test/node/run-helper-tests.mjs` from the plugin root.

import { test } from "node:test";
import assert from "node:assert/strict";

import {
  MENTION_RE,
  extractMentionedUsernames,
  pendingMentions,
} from "../../assets/javascripts/discourse/lib/whisper-mentions.js";
import { computeReplyAudience } from "../../assets/javascripts/discourse/lib/reply-audience.js";

// ---------- extractMentionedUsernames ----------

test("empty string returns []", () => {
  assert.deepEqual(extractMentionedUsernames(""), []);
});
test("null returns []", () => {
  assert.deepEqual(extractMentionedUsernames(null), []);
});
test("undefined returns []", () => {
  assert.deepEqual(extractMentionedUsernames(undefined), []);
});
test("number returns []", () => {
  assert.deepEqual(extractMentionedUsernames(42), []);
});
test("object returns []", () => {
  assert.deepEqual(extractMentionedUsernames({ reply: "@alice" }), []);
});
test("no @ returns []", () => {
  assert.deepEqual(extractMentionedUsernames("hello world"), []);
});
test("mention at start", () => {
  assert.deepEqual(extractMentionedUsernames("@alice hi"), ["alice"]);
});
test("mention after space", () => {
  assert.deepEqual(extractMentionedUsernames("hi @alice"), ["alice"]);
});
test("mention after newline", () => {
  assert.deepEqual(extractMentionedUsernames("a\n@alice"), ["alice"]);
});
test("mention after tab", () => {
  assert.deepEqual(extractMentionedUsernames("a\t@alice"), ["alice"]);
});
test("mention after carriage return", () => {
  assert.deepEqual(extractMentionedUsernames("a\r@alice"), ["alice"]);
});
test("mention after opening paren", () => {
  assert.deepEqual(extractMentionedUsernames("(@alice)"), ["alice"]);
});
test("nested parens", () => {
  assert.deepEqual(extractMentionedUsernames("((@alice))"), ["alice"]);
});
test("does NOT match email foo@bar", () => {
  assert.deepEqual(extractMentionedUsernames("foo@bar.com"), []);
});
test("does NOT match email in sentence", () => {
  assert.deepEqual(extractMentionedUsernames("email me at foo@bar.com please"), []);
});
test("matches real mention while ignoring adjacent email", () => {
  assert.deepEqual(extractMentionedUsernames("hi @alice, email foo@bar.com"), ["alice"]);
});
test("multiple mentions", () => {
  assert.deepEqual(extractMentionedUsernames("@alice and @bob"), ["alice", "bob"]);
});
test("three mentions across lines", () => {
  assert.deepEqual(extractMentionedUsernames("@alice\n@bob\n@carol"), ["alice", "bob", "carol"]);
});
test("dedupes exact duplicates", () => {
  assert.deepEqual(extractMentionedUsernames("@alice @alice @alice"), ["alice"]);
});
test("dedupes case-insensitively, keeps first casing", () => {
  assert.deepEqual(extractMentionedUsernames("@Alice @alice @ALICE"), ["Alice"]);
});
test("username with dot", () => {
  assert.deepEqual(extractMentionedUsernames("@first.last"), ["first.last"]);
});
test("username with underscore", () => {
  assert.deepEqual(extractMentionedUsernames("@first_last"), ["first_last"]);
});
test("username with dash", () => {
  assert.deepEqual(extractMentionedUsernames("@first-last"), ["first-last"]);
});
test("username with digits", () => {
  assert.deepEqual(extractMentionedUsernames("@user123"), ["user123"]);
});
test("only digits", () => {
  assert.deepEqual(extractMentionedUsernames("@12345"), ["12345"]);
});
test("exactly 60 chars OK", () => {
  const max = "a".repeat(60);
  assert.deepEqual(extractMentionedUsernames(`@${max}`), [max]);
});
test("caps at 60 chars", () => {
  const long = "a".repeat(61);
  assert.strictEqual(extractMentionedUsernames(`@${long}`)[0].length, 60);
});
test("bare @ with space", () => {
  assert.deepEqual(extractMentionedUsernames("@ alice"), []);
});
test("bare @ no username", () => {
  assert.deepEqual(extractMentionedUsernames("@"), []);
});
test("non-ASCII @你好", () => {
  assert.deepEqual(extractMentionedUsernames("@你好"), []);
});
test("emoji", () => {
  assert.deepEqual(extractMentionedUsernames("@🍕"), []);
});
test("stops at space", () => {
  assert.deepEqual(extractMentionedUsernames("@alice bob"), ["alice"]);
});
test("stops at comma", () => {
  assert.deepEqual(extractMentionedUsernames("@alice, @bob"), ["alice", "bob"]);
});
test("greedy-consumes dot in tail", () => {
  assert.deepEqual(extractMentionedUsernames("@alice. rest"), ["alice."]);
});
test("@@ at start is not matched", () => {
  assert.deepEqual(extractMentionedUsernames("@@alice"), []);
});
test("hi @@alice is not matched", () => {
  assert.deepEqual(extractMentionedUsernames("hi @@alice"), []);
});
test("foo@alice mid-word is not matched", () => {
  assert.deepEqual(extractMentionedUsernames("foo@alice"), []);
});
test("slash prefix not matched (site.com/@alice)", () => {
  assert.deepEqual(extractMentionedUsernames("site.com/@alice"), []);
});
test("backtick prefix not matched", () => {
  assert.deepEqual(extractMentionedUsernames("`@alice`"), []);
});
test("> prefix (no space) not matched", () => {
  assert.deepEqual(extractMentionedUsernames(">@alice"), []);
});
test("> space prefix matched", () => {
  assert.deepEqual(extractMentionedUsernames("> @alice"), ["alice"]);
});
test("@! not matched", () => {
  assert.deepEqual(extractMentionedUsernames("@!"), []);
});
test("@% not matched", () => {
  assert.deepEqual(extractMentionedUsernames("@%"), []);
});
test("@alice!", () => {
  assert.deepEqual(extractMentionedUsernames("@alice!"), ["alice"]);
});
test("@alice?", () => {
  assert.deepEqual(extractMentionedUsernames("@alice?"), ["alice"]);
});
test("@alice: hi", () => {
  assert.deepEqual(extractMentionedUsernames("@alice: hi"), ["alice"]);
});
test("\\n@alice at start", () => {
  assert.deepEqual(extractMentionedUsernames("\n@alice"), ["alice"]);
});
test("MENTION_RE has global flag", () => {
  assert.equal(MENTION_RE.global, true);
});
test("re-exec state is reset between calls", () => {
  assert.deepEqual(extractMentionedUsernames("@alice"), ["alice"]);
  assert.deepEqual(extractMentionedUsernames("@bob"), ["bob"]);
});
test("50 mentions at once", () => {
  const parts = Array.from({ length: 50 }, (_, i) => `@user${i}`);
  const out = extractMentionedUsernames(parts.join(" "));
  assert.equal(out.length, 50);
  assert.equal(out[0], "user0");
  assert.equal(out[49], "user49");
});

// ---------- pendingMentions ----------

test("pending: nothing mentioned", () => {
  assert.deepEqual(pendingMentions("hi", ["alice"]), []);
});
test("pending: all armed", () => {
  assert.deepEqual(pendingMentions("@alice @bob", ["alice", "bob"]), []);
});
test("pending: only unarmed returned", () => {
  assert.deepEqual(pendingMentions("@alice @bob", ["alice"]), ["bob"]);
});
test("pending: case-insensitive armed match", () => {
  assert.deepEqual(pendingMentions("@Alice @Bob", ["ALICE"]), ["Bob"]);
});
test("pending: null armed", () => {
  assert.deepEqual(pendingMentions("@alice", null), ["alice"]);
});
test("pending: undefined armed", () => {
  assert.deepEqual(pendingMentions("@alice", undefined), ["alice"]);
});
test("pending: empty armed", () => {
  assert.deepEqual(pendingMentions("@alice", []), ["alice"]);
});
test("pending: skips non-string armed entries", () => {
  assert.deepEqual(pendingMentions("@alice", [null, 42, "alice"]), []);
});
test("pending: empty reply", () => {
  assert.deepEqual(pendingMentions("", ["alice"]), []);
});
test("pending: null reply", () => {
  assert.deepEqual(pendingMentions(null, ["alice"]), []);
});

// ---------- computeReplyAudience ----------

test("audience: null post → []", () => {
  assert.deepEqual(computeReplyAudience(null, 1), []);
});
test("audience: undefined post → []", () => {
  assert.deepEqual(computeReplyAudience(undefined, 1), []);
});
test("audience: null currentUserId → []", () => {
  assert.deepEqual(computeReplyAudience({ user_id: 1 }, null), []);
});
test("audience: undefined currentUserId → []", () => {
  assert.deepEqual(computeReplyAudience({ user_id: 1 }, undefined), []);
});
test("audience: currentUserId 0 → []", () => {
  assert.deepEqual(computeReplyAudience({ user_id: 1 }, 0), []);
});
test("audience: includes author + all targets", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [
      { id: 2, username: "bob", avatar_template: "/b.png" },
      { id: 3, username: "carol", avatar_template: "/c.png" },
    ],
  };
  assert.deepEqual(
    computeReplyAudience(post, 99).map((u) => u.id).sort(),
    [1, 2, 3]
  );
});
test("audience: excludes current user (author)", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [
      { id: 2, username: "bob", avatar_template: "/b.png" },
      { id: 3, username: "carol", avatar_template: "/c.png" },
    ],
  };
  assert.deepEqual(
    computeReplyAudience(post, 1).map((u) => u.id).sort(),
    [2, 3]
  );
});
test("audience: excludes current user (target)", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [
      { id: 2, username: "bob", avatar_template: "/b.png" },
      { id: 3, username: "carol", avatar_template: "/c.png" },
    ],
  };
  assert.deepEqual(
    computeReplyAudience(post, 2).map((u) => u.id).sort(),
    [1, 3]
  );
});
test("audience: dedupes author-in-targets", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [
      { id: 1, username: "alice", avatar_template: "/a.png" },
      { id: 2, username: "bob", avatar_template: "/b.png" },
    ],
  };
  const out = computeReplyAudience(post, 99);
  assert.equal(out.length, 2);
  assert.deepEqual(
    out.map((u) => u.id).sort(),
    [1, 2]
  );
});
test("audience: dedupes duplicate targets", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [
      { id: 2, username: "bob", avatar_template: "/b.png" },
      { id: 2, username: "bob", avatar_template: "/b.png" },
    ],
  };
  assert.equal(computeReplyAudience(post, 99).length, 2);
});
test("audience: preserves id/username/avatar_template", () => {
  const post = { user_id: 1, username: "alice", avatar_template: "/a.png", whisper_targets: [] };
  assert.deepEqual(computeReplyAudience(post, 99), [
    { id: 1, username: "alice", avatar_template: "/a.png" },
  ]);
});
test("audience: missing whisper_targets", () => {
  const post = { user_id: 1, username: "alice", avatar_template: "/a.png" };
  assert.deepEqual(computeReplyAudience(post, 99).map((u) => u.id), [1]);
});
test("audience: non-array whisper_targets", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: "nope",
  };
  assert.deepEqual(computeReplyAudience(post, 99).map((u) => u.id), [1]);
});
test("audience: skips null/undefined target entries", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [null, undefined, { id: 2, username: "bob", avatar_template: "/b.png" }],
  };
  assert.deepEqual(
    computeReplyAudience(post, 99).map((u) => u.id).sort(),
    [1, 2]
  );
});
test("audience: skips targets with falsy id", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [
      { id: 0, username: "ghost", avatar_template: "/g.png" },
      { id: null, username: "null", avatar_template: "/n.png" },
      { id: 2, username: "bob", avatar_template: "/b.png" },
    ],
  };
  assert.deepEqual(
    computeReplyAudience(post, 99).map((u) => u.id).sort(),
    [1, 2]
  );
});
test("audience: falsy author id + empty targets → []", () => {
  const post = { user_id: 0, username: "ghost", avatar_template: "/g.png", whisper_targets: [] };
  assert.deepEqual(computeReplyAudience(post, 99), []);
});
test("audience: falsy author id + valid target", () => {
  const post = {
    user_id: 0,
    username: "ghost",
    avatar_template: "/g.png",
    whisper_targets: [{ id: 2, username: "bob", avatar_template: "/b.png" }],
  };
  assert.deepEqual(computeReplyAudience(post, 99).map((u) => u.id), [2]);
});
test("audience: ordering (author first, then targets in order)", () => {
  const post = {
    user_id: 10,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [
      { id: 3, username: "bob", avatar_template: "/b.png" },
      { id: 7, username: "carol", avatar_template: "/c.png" },
      { id: 5, username: "dave", avatar_template: "/d.png" },
    ],
  };
  assert.deepEqual(
    computeReplyAudience(post, 99).map((u) => u.id),
    [10, 3, 7, 5]
  );
});
test("audience: large target list (50)", () => {
  const targets = [];
  for (let i = 2; i <= 50; i++) {
    targets.push({ id: i, username: `u${i}`, avatar_template: `/a${i}.png` });
  }
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: targets,
  };
  assert.equal(computeReplyAudience(post, 999).length, 50);
});
test("audience: string currentUserId doesn't strict-match number user_id", () => {
  // Documented behavior: strict === comparison. '1' !== 1, so the user stays
  // in the audience. Real code paths always use numeric IDs so this isn't a
  // production concern, but we lock the behavior here.
  const post = { user_id: 1, username: "alice", avatar_template: "/a.png", whisper_targets: [] };
  assert.deepEqual(computeReplyAudience(post, "1").map((u) => u.id), [1]);
});
test("audience: number user_id survives when currentUserId is a different number", () => {
  const post = { user_id: 1, username: "alice", avatar_template: "/a.png", whisper_targets: [] };
  assert.deepEqual(computeReplyAudience(post, 2).map((u) => u.id), [1]);
});
test("audience: target with missing username still included", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [{ id: 2, avatar_template: "/b.png" }],
  };
  const out = computeReplyAudience(post, 99);
  assert.deepEqual(out.map((u) => u.id).sort(), [1, 2]);
});
test("audience: target with missing avatar_template still included", () => {
  const post = {
    user_id: 1,
    username: "alice",
    avatar_template: "/a.png",
    whisper_targets: [{ id: 2, username: "bob" }],
  };
  const out = computeReplyAudience(post, 99);
  const bob = out.find((u) => u.id === 2);
  assert.equal(bob.username, "bob");
  assert.equal(bob.avatar_template, undefined);
});

// ---------- more mention regex edges ----------

test("username followed by non-ASCII stops at first non-ASCII char", () => {
  // "@alice你好" — Chinese chars are not in [a-zA-Z0-9_.\-] so regex stops at "alice"
  assert.deepEqual(extractMentionedUsernames("@alice你好"), ["alice"]);
});
test("username with emoji after it stops at emoji", () => {
  assert.deepEqual(extractMentionedUsernames("@alice🍕"), ["alice"]);
});
test("non-breaking space (\\u00A0) is a valid prefix via \\s", () => {
  // JS \s includes \u00A0.
  assert.deepEqual(extractMentionedUsernames("a\u00A0@alice"), ["alice"]);
});
test("vertical tab is a valid prefix", () => {
  assert.deepEqual(extractMentionedUsernames("a\v@alice"), ["alice"]);
});
test("form feed is a valid prefix", () => {
  assert.deepEqual(extractMentionedUsernames("a\f@alice"), ["alice"]);
});
test("square bracket [@alice] not matched (no [ in prefix set)", () => {
  assert.deepEqual(extractMentionedUsernames("[@alice]"), []);
});
test("curly brace {@alice} not matched", () => {
  assert.deepEqual(extractMentionedUsernames("{@alice}"), []);
});
test("double-quote \"@alice\" not matched", () => {
  assert.deepEqual(extractMentionedUsernames('"@alice"'), []);
});
test("single-quote '@alice' not matched", () => {
  assert.deepEqual(extractMentionedUsernames("'@alice'"), []);
});
test("markdown # heading @alice via space", () => {
  assert.deepEqual(extractMentionedUsernames("# @alice"), ["alice"]);
});
test("hyphen-only username @-", () => {
  assert.deepEqual(extractMentionedUsernames("@-"), ["-"]);
});
test("underscore-only username @_", () => {
  assert.deepEqual(extractMentionedUsernames("@_"), ["_"]);
});
test("dot-only username @.", () => {
  assert.deepEqual(extractMentionedUsernames("@."), ["."]);
});
test("mention spanning very long input with many boundaries", () => {
  const input = "prefix " + "@u1 ".repeat(100) + "suffix";
  const out = extractMentionedUsernames(input);
  assert.equal(out.length, 1); // deduped to one
  assert.equal(out[0], "u1");
});

// pending + mention-extract interaction

test("pendingMentions across multi-line reply", () => {
  assert.deepEqual(
    pendingMentions("hi @alice\nand @bob\nand @carol", ["alice"]),
    ["bob", "carol"]
  );
});
test("pendingMentions ignores pure email in reply", () => {
  assert.deepEqual(
    pendingMentions("hi @alice, email foo@bar.com", []),
    ["alice"]
  );
});
