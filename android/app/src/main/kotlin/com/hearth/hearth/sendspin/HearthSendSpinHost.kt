package com.hearth.hearth.sendspin

import com.sendspindroid.sendspin.SendSpinHost
import com.sendspindroid.sendspin.crypto.ClientIdentity
import com.sendspindroid.sendspin.crypto.PairingConfigStore
import com.sendspindroid.sendspin.crypto.TrustStore
import com.sendspindroid.sendspin.pairing.PairingOutcome
import timber.log.Timber

/**
 * Settings from the last `configure`, secrets from [SendspinSecrets]. A
 * server's output delay is held here and reported to Dart, which writes it
 * to `hub_config.json` and hands it back on the next `configure`.
 */
class HearthSendSpinHost(
    private val config: SendspinConfig,
    private val secrets: SendspinSecrets,
    override val softwareVersion: String,
    private val onOutputDelay: (Int) -> Unit,
    private val onPairingChanged: () -> Unit,
) : SendSpinHost {
    @Volatile
    private var outputDelay = config.outputDelayMs

    @Volatile
    private var pairingFailures = 0

    // A kiosk on mains power with memory to spare.
    override val lowMemoryMode: Boolean get() = false
    override val highPowerMode: Boolean get() = true

    // SendspinDroid's default.
    override fun preferredCodec(): String = "opus"

    override fun outputDelayMs(): Int = outputDelay

    override fun setOutputDelayMs(delayMs: Int) {
        outputDelay = delayMs
        onOutputDelay(delayMs)
    }

    override fun clientIdentity(): ClientIdentity = secrets.identity

    override fun trustStore(): TrustStore = secrets.trustStore

    override fun pairingConfigStore(): PairingConfigStore =
        secrets.pairingConfigStore { config.unpairedAccess }

    // Only the dynamic pairing code uses these, and it is off.
    override fun pairingCodeFailures(): Int = pairingFailures

    override fun setPairingCodeFailures(value: Int) {
        pairingFailures = value
    }

    // Hearth lists paired servers by count, not by name.
    override fun rememberServerName(serverId: String, name: String) {}

    override fun forgetServerName(serverId: String) {}

    override fun onPairingOutcome(outcome: PairingOutcome) {
        Timber.i("Sendspin pairing: $outcome")
        onPairingChanged()
    }
}
