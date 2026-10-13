package cjls.macro_host

import std.sync.*
import std.time.MonoTime

/**
 * The delays between attempts at what keeps failing for a while: `first`, then twice the last, never past `cap`,
 * from `first` again after `reset`.
 */
class Backoff {
    private var delay: Duration

    Backoff(private let first: Duration, private let cap: Duration) {
        delay = first
    }

    /**
     * The delay before the next attempt.
     */
    func next(): Duration {
        let now = delay
        delay = if (delay * 2 > cap) {
            cap
        } else {
            delay * 2
        }
        now
    }

    func reset(): Unit {
        delay = first
    }
}

/**
 * What the host's thread does next (`Wakeups.take`).
 */
enum NextWork {
    // expand, and build first if `true`
    | Work(Bool)
    | Ended
    // wait until woken, or for at most the duration
    | WaitFor(?Duration)
}

/**
 * When the host's thread works: once woken, with a build if any wake asked for one, and again with a build once a
 * build another server held the lock of is due to be tried again (D104). The delays are `Backoff`'s: 1 s, doubled
 * up to 30 s, from 1 s again once a build runs. Any wake starts over: a retry waiting is built at once, and its
 * delays from 1 s.
 */
class Wakeups {
    private let lock = Mutex()
    // made under `lock`: `condition` throws otherwise
    private let woken: Condition
    // guarded by `lock`
    private var work = false
    private var build = false
    private var stopped = false
    private var retryAt: ?MonoTime = None
    private let backoff = Backoff(Duration.second, Duration.second * 30)

    init() {
        woken = synchronized(lock) {
            lock.condition()
        }
    }

    func wake(build: Bool): Unit {
        synchronized(lock) {
            work = true
            this.build = this.build || build || retryAt.isSome()
            retryAt = None
            backoff.reset()
            woken.notifyAll()
        }
    }

    func stop(): Unit {
        synchronized(lock) {
            stopped = true
            woken.notifyAll()
        }
    }

    func isStopped(): Bool {
        synchronized(lock) {
            stopped
        }
    }

    /**
     * What a build did at `now`: `ran`, or found the lock another server holds, to be tried again later.
     */
    func built(ran: Bool, now: MonoTime): Unit {
        synchronized(lock) {
            if (ran) {
                backoff.reset()
            } else {
                retryAt = now + backoff.next()
            }
        }
    }

    /**
     * Waits for work: whether to build first, or `None` once stopped. `clock` is a test's.
     */
    func next(clock!: () -> MonoTime = {=> MonoTime.now()}): ?Bool {
        synchronized(lock) {
            while (true) {
                match (take(clock())) {
                    case Work(build) => return build
                    case Ended => return None
                    case WaitFor(None) => woken.wait()
                    case WaitFor(Some(left)) => woken.wait(timeout: left)
                }
            }
            None
        }
    }

    /**
     * What to do at `now`: the work woken for or a retry due, taken; else how long to wait.
     */
    func take(now: MonoTime): NextWork {
        synchronized(lock) {
            if (stopped) {
                return Ended
            }
            if (let Some(at) <- retryAt && at <= now) {
                work = true
                build = true
                retryAt = None
            }
            if (!work) {
                return WaitFor(retryAt.map {at => at - now})
            }
            let wanted = build
            work = false
            build = false
            Work(wanted)
        }
    }
}
