package cjls.handlers

import std.collection.ArrayList
import stdx.log.Logger
import fjson.JsonValue
import cjls.lsp_types.*
import cjls.server.*
import cjls.macros.LspHandler

/**
 * The settings changed in the client. One that answers `workspace/configuration` is asked for them,
 * as R1 asks: what it sends here may be nothing (VS Code sends `null`, LSP's issue 676). One that
 * does not answer it sends them here, under the section `cjls`.
 */
@LspHandler
func handleDidChangeConfiguration(loop: Loop, client: Client, logger: Logger, params: DidChangeConfigurationParams): Unit {
    if (loop.state.pullsSettings) {
        pullSettings(loop, client, logger)
    } else if (let Some(section) <- params.settings.get(SETTINGS_SECTION)) {
        changeSettings(loop, client, logger, section)
    }
}

/**
 * The settings `initializationOptions` holds, the first the server has; the defaults if it holds
 * none. What is wrong in them is told to the log and the user.
 */
func initialSettings(options: ?JsonValue, client: Client, logger: Logger): Settings {
    let problems = ArrayList<String>()
    let settings = options.flatMap {options => settingsOf(options, "`initializationOptions`", problems)}
    reportSettingsProblems(client, logger, problems)
    settings ?? Settings()
}

/**
 * The settings `json` holds, as R1 takes them: `None` for `null` or an empty object, which leave
 * the settings as they are (a client with nothing set keeps its `initializationOptions`), and for
 * what is no object, which `problems` is told of; any other object is every setting, one it leaves
 * out at its default.
 */
func settingsOf(json: JsonValue, what: String, problems: ArrayList<String>): ?Settings {
    match (json) {
        case JsonValue.JsonNull => None
        case JsonValue.JsonObject(members) where members.isEmpty() => None
        case JsonValue.JsonObject(_) => Settings.read(json, problems)
        case _ =>
            problems.add("${what} is not an object: ${json}")
            None
    }
}

/**
 * Asks the client for the section `cjls` of its configuration, if it answers such a request, and
 * takes the answer as the settings, on a thread of its own: the answer comes through the read loop.
 * An answer to an asking that a later one ended is not taken.
 */
func pullSettings(loop: Loop, client: Client, logger: Logger): Unit {
    let state = loop.state
    if (!state.pullsSettings) {
        return
    }
    let pull = state.beginSettingsPull()
    let answer = try {
        client.request(ConfigurationRequestSpec(),
            ConfigurationParams(items: [ConfigurationItem(section: SETTINGS_SECTION)]))
    } catch (e: Exception) {
        logger.warn("the settings were not asked for", [("error", e.message)])
        return
    }
    loop.start(logger) {
        let sections = try {
            answer.await()
        } catch (e: Exception) {
            if (client.isClosed()) {
                logger.debug("the settings were not answered", [("reason", "the connection is closed")])
            } else {
                logger.warn("the settings were not answered", [("error", e.message)])
            }
            return
        }
        if (let Some(section) <- sections.first) {
            loop.write {
                state: ServerState => if (state.isLastSettingsPull(pull)) {
                    changeSettings(loop, client, logger, section)
                }
            }
        }
    }
}

/**
 * Takes the section `cjls` of the client's configuration as the settings (`settingsOf`); settings
 * that changed find the project again, as every setting there is says where it or the SDK is.
 */
func changeSettings(loop: Loop, client: Client, logger: Logger, section: JsonValue): Unit {
    let problems = ArrayList<String>()
    let settings = settingsOf(section, "the section `${SETTINGS_SECTION}`", problems)
    reportSettingsProblems(client, logger, problems)
    let state = loop.state
    match (settings) {
        case Some(settings) where settings != state.settings =>
            state.settings = settings
            logger.info("the settings changed")
            startLoad(loop, client, logger)
        case _ => ()
    }
}

/**
 * Asks the client to tell the server when the section `cjls` changes, if it takes a registration
 * for that: VS Code tells nothing otherwise.
 */
func watchSettings(state: ServerState, client: Client, logger: Logger): Unit {
    if (!state.registersSettings) {
        return
    }
    let registration = DidChangeConfigurationNotificationSpec().registration(state.registrationId(),
        DidChangeConfigurationRegistrationOptions(section: StringOrStrings.AsString(SETTINGS_SECTION)))
    client.request(RegistrationRequestSpec(), RegistrationParams(registrations: [registration]), logger)
}

/**
 * Tells the log and the user what in the settings was not taken.
 */
func reportSettingsProblems(client: Client, logger: Logger, problems: ArrayList<String>): Unit {
    if (problems.isEmpty()) {
        return
    }
    for (problem in problems) {
        logger.warn("a setting is not taken", [("problem", problem)])
    }
    showWarning(client, logger, "cjls: settings not taken: ${String.join(problems.toArray(), delimiter: "; ")}")
}
