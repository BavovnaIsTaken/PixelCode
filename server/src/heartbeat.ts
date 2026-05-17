/**
 * WebSocket liveness tracker.
 *
 * TCP keep-alive alone doesn't reliably detect "zombie" sockets on mobile
 * networks (Wi-Fi ↔ LTE handoffs, NAT timeouts). Without an application-level
 * ping the server can hold an in-flight chat query against a peer that is
 * already gone — and the client believes itself connected while no traffic
 * actually flows.
 *
 * This monitor is intentionally pure: it's driven by `tick()` plus pong/connect
 * events fed in from the WebSocketServer layer. The driver picks the cadence
 * (default: 20 s ping interval, 3 missed pings → terminate ≈ 60 s).
 */
export interface HeartbeatPolicy {
  /** How many consecutive missed pings before a client is declared dead. */
  readonly maxMissedPings: number;
}

export const DEFAULT_HEARTBEAT_POLICY: HeartbeatPolicy = {
  maxMissedPings: 3,
};

export class HeartbeatMonitor<T> {
  private readonly missed = new Map<T, number>();

  constructor(private readonly policy: HeartbeatPolicy = DEFAULT_HEARTBEAT_POLICY) {}

  /** Register a freshly-connected client. */
  onConnect(client: T): void {
    this.missed.set(client, 0);
  }

  /** Reset the missed-ping counter — a pong arrived. */
  onPong(client: T): void {
    if (this.missed.has(client)) this.missed.set(client, 0);
  }

  /** Drop bookkeeping for a client that closed (clean or terminated). */
  onDisconnect(client: T): void {
    this.missed.delete(client);
  }

  /**
   * Drive one heartbeat cycle. Returns the partition:
   *   - `terminate`: clients that exceeded `maxMissedPings` — driver should
   *     call `ws.terminate()` and `onDisconnect()` to drop them.
   *   - `ping`: surviving clients to ping. Their missed counter is incremented
   *     in this call; an arriving pong resets it before the next tick.
   *
   * Splitting the partition (instead of letting the driver re-scan)
   * keeps tick() the single point that can mutate the counter and makes the
   * "terminate vs ping" decision testable without any WebSocket machinery.
   */
  tick(): { terminate: T[]; ping: T[] } {
    const terminate: T[] = [];
    const ping: T[] = [];
    for (const [client, count] of this.missed) {
      if (count >= this.policy.maxMissedPings) {
        terminate.push(client);
      } else {
        this.missed.set(client, count + 1);
        ping.push(client);
      }
    }
    for (const client of terminate) this.missed.delete(client);
    return { terminate, ping };
  }

  /** Visible for testing — the current missed-ping count for a client. */
  missedCount(client: T): number {
    return this.missed.get(client) ?? 0;
  }

  get size(): number {
    return this.missed.size;
  }
}
