/**
 * Tests for HeartbeatMonitor — the application-level WS liveness tracker.
 *
 * TCP keep-alive doesn't catch mobile half-open sockets (Wi-Fi↔LTE handoff,
 * NAT timeout). The monitor partitions each tick into "terminate" (missed
 * the threshold) vs "ping" (still alive enough to probe) so the WSS layer
 * can be a thin driver and the decision logic stays pure / unit-testable.
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { HeartbeatMonitor } from "../src/heartbeat.js";

test("fresh client never terminates before any ticks elapse", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 3 });
  hm.onConnect("a");
  const { terminate, ping } = hm.tick();
  assert.deepEqual(terminate, []);
  assert.deepEqual(ping, ["a"]);
});

test("client missing N consecutive pings is terminated on the N+1th tick", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 3 });
  hm.onConnect("a");
  // Three "no pong arrived" cycles.
  hm.tick(); // count 0→1
  hm.tick(); // count 1→2
  hm.tick(); // count 2→3
  const fourth = hm.tick(); // count 3 ≥ threshold → terminate
  assert.deepEqual(fourth.terminate, ["a"]);
  assert.deepEqual(fourth.ping, []);
});

test("pong resets the counter — survives indefinite ticks with timely pongs", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 3 });
  hm.onConnect("a");
  for (let i = 0; i < 20; i++) {
    hm.tick();
    hm.onPong("a"); // pong arrives between ticks
  }
  const { terminate } = hm.tick();
  assert.deepEqual(terminate, []);
  assert.equal(hm.missedCount("a"), 1, "exactly one tick has incremented since last pong");
});

test("partial pong recovery: 2 missed → pong → counter back to 0", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 3 });
  hm.onConnect("a");
  hm.tick();
  hm.tick();
  assert.equal(hm.missedCount("a"), 2);
  hm.onPong("a");
  assert.equal(hm.missedCount("a"), 0);
});

test("multiple clients are tracked independently", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 2 });
  hm.onConnect("alive");
  hm.onConnect("zombie");
  hm.tick();           // both →1
  hm.onPong("alive");   // alive →0
  hm.tick();           // alive →1, zombie →2
  const third = hm.tick(); // zombie 2 ≥ threshold → terminate; alive 1→2
  assert.deepEqual(third.terminate, ["zombie"]);
  assert.deepEqual(third.ping, ["alive"]);
});

test("onDisconnect drops the client entirely", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 3 });
  hm.onConnect("a");
  hm.onConnect("b");
  hm.onDisconnect("a");
  const { ping } = hm.tick();
  assert.deepEqual(ping, ["b"]);
  assert.equal(hm.size, 1);
});

test("terminated clients are dropped — tick() is idempotent on a dead set", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 1 });
  hm.onConnect("a");
  hm.tick(); // 0→1
  const second = hm.tick(); // 1 ≥ threshold → terminate
  assert.deepEqual(second.terminate, ["a"]);
  // After termination, the next tick must see an empty set, NOT re-process.
  const third = hm.tick();
  assert.deepEqual(third.terminate, []);
  assert.deepEqual(third.ping, []);
  assert.equal(hm.size, 0);
});

test("pong from an unknown client is ignored — no resurrection", () => {
  const hm = new HeartbeatMonitor<string>({ maxMissedPings: 3 });
  hm.onPong("ghost");
  assert.equal(hm.size, 0);
  assert.equal(hm.missedCount("ghost"), 0);
});
