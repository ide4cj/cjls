package cjls.server

/**
 * What runs the workspace's macros on a thread of its own (`cjls.macro_host`, D104), as the server tells it there
 * is work: neither call waits for the work to be done.
 */
public interface MacroWork {
    /**
     * The files changed: their calls may need asking; `build`, the files on disk did, and the macro packages may
     * need building.
     */
    func wake(build: Bool): Unit

    /**
     * Ends the work, and the macro server with it.
     */
    func stop(): Unit
}
