package com.hearth.hearth.sendspin

/**
 * What Dart hands over on `configure`. `hub_config.json` is the source of
 * truth; only the pairing secrets are kept natively (see [SendspinSecrets]).
 */
data class SendspinConfig(
    val enabled: Boolean,
    val playerName: String,
    val serverUrl: String,
    val unpairedAccess: Boolean,
    val outputDelayMs: Int,
    val lastPlaybackServerId: String?,
) {
    /** Whether there is anything for the service to run. */
    val active: Boolean get() = enabled && playerName.isNotBlank()

    companion object {
        fun fromArguments(args: Map<*, *>) = SendspinConfig(
            enabled = args["enabled"] as? Boolean ?: false,
            playerName = args["playerName"] as? String ?: "",
            serverUrl = args["serverUrl"] as? String ?: "",
            unpairedAccess = args["unpairedAccess"] as? Boolean ?: true,
            outputDelayMs = (args["outputDelayMs"] as? Number)?.toInt() ?: 0,
            lastPlaybackServerId = (args["lastPlaybackServerId"] as? String)?.ifEmpty { null },
        )
    }
}
