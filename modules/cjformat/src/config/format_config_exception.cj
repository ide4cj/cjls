package cjformat.config

/**
 * A project formatter configuration could not be read or validated; the message names its path.
 */
public class FormatConfigException <: Exception {
    public init(message: String) {
        super(message)
    }

    public override func getClassName(): String {
        "FormatConfigException"
    }
}
