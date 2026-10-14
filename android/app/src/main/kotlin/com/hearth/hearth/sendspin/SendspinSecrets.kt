package com.hearth.hearth.sendspin

import android.content.Context
import android.util.AtomicFile
import com.sendspindroid.sendspin.crypto.Base64Url
import com.sendspindroid.sendspin.crypto.ClientIdentity
import com.sendspindroid.sendspin.crypto.InMemoryTrustStore
import com.sendspindroid.sendspin.crypto.PairingConfig
import com.sendspindroid.sendspin.crypto.PairingConfigStore
import com.sendspindroid.sendspin.crypto.Psk
import com.sendspindroid.sendspin.crypto.PskId
import com.sendspindroid.sendspin.crypto.PskRecordCodec
import com.sendspindroid.sendspin.crypto.TrustStore
import com.sendspindroid.sendspin.crypto.secureRandomBytes
import com.sendspindroid.sendspin.pairing.PairingToken
import java.io.File
import java.io.IOException
import timber.log.Timber

/**
 * The device's Sendspin key pair, pairing PSK and trust records, in the
 * app's private files under `sendspin/`. The only Sendspin state Hearth keeps
 * outside `hub_config.json`, as the Pi keeps its identity in a file of its
 * own. Clearing the app's data unpairs it from every server.
 *
 * One instance per process: the client API asks for "the same store on
 * every call", and two instances could mint two identities.
 */
class SendspinSecrets private constructor(dir: File) {
    private val identityFile = File(dir, "identity")
    private val pairingPskFile = File(dir, "pairing_psk")
    private val trustFile = File(dir, "trust.json")

    init {
        dir.mkdirs()
    }

    /** Minted on first use. Never replaced: a new key unpairs every server. */
    val identity: ClientIdentity by lazy {
        val key = loadOrMint(identityFile, ClientIdentity.KEY_SIZE)
        ClientIdentity(key)
    }

    /** Long-lived, like the identity; a pairing does not consume it. */
    private val pairingPsk: ByteArray by lazy { loadOrMint(pairingPskFile, Psk.PSK_SIZE) }

    val trustStore: TrustStore by lazy {
        val initial = read(trustFile)?.let(PskRecordCodec::decode).orEmpty()
        object : InMemoryTrustStore(
            initial = initial,
            pairingPskId = PskId.derive(pairingPsk),
            // Private app storage, not the Keystore.
            storageIsEncrypted = false,
        ) {
            override fun onChanged(): Boolean = writeAtomically(trustFile, PskRecordCodec.encode(listRecords()))
        }
    }

    /** The pairing options come from `configure`; only the PSK is stored here. */
    fun pairingConfigStore(unpairedAccess: () -> Boolean): PairingConfigStore = object : PairingConfigStore {
        override fun load() = PairingConfig(
            pairingPsk = pairingPsk,
            unpairedAccessEnabled = unpairedAccess(),
            // Off in the first version: nothing on screen shows a code.
            dynamicPairingCodeEnabled = false,
        )

        // HubConfig owns the setting, and nothing native changes it.
        override fun setUnpairedAccess(enabled: Boolean) = false

        override fun rotatePairingPsk(newPsk: ByteArray, claimedPskIds: Set<String>) =
            PairingConfigStore.RotateResult.StorageFailed
    }

    /** The `SP:0…` token. It carries the pairing PSK: never log it. */
    fun pairingToken(): String = PairingToken.encode(identity.publicKey, pairingPsk)

    /**
     * A key read from [file], or a fresh one written there. An unreadable
     * key is not overwritten: minting over it would unpair every server and
     * report nothing.
     */
    private fun loadOrMint(file: File, size: Int): ByteArray {
        read(file)?.let { text ->
            val bytes = Base64Url.decodeOrNull(text.trim())
            check(bytes != null && bytes.size == size) { "${file.name} is unreadable" }
            return bytes
        }
        val fresh = secureRandomBytes(size)
        if (!writeAtomically(file, Base64Url.encode(fresh))) throw IOException("cannot write ${file.name}")
        Timber.i("Created Sendspin ${file.name}")
        return fresh
    }

    /** Null when there is no file; AtomicFile restores an interrupted write's backup. */
    private fun read(file: File): String? {
        val atomic = AtomicFile(file)
        if (!atomic.baseFile.exists() && !File(file.path + ".bak").exists()) return null
        return String(atomic.readFully(), Charsets.UTF_8)
    }

    /** Synced before it replaces the old file, so a power cut cannot leave it empty. */
    private fun writeAtomically(file: File, text: String): Boolean {
        val atomic = AtomicFile(file)
        val out = try {
            atomic.startWrite()
        } catch (e: IOException) {
            Timber.e(e, "Cannot write ${file.name}")
            return false
        }
        return try {
            out.write(text.toByteArray(Charsets.UTF_8))
            atomic.finishWrite(out)
            true
        } catch (e: IOException) {
            atomic.failWrite(out)
            Timber.e(e, "Cannot write ${file.name}")
            false
        }
    }

    companion object {
        @Volatile
        private var instance: SendspinSecrets? = null

        fun get(context: Context): SendspinSecrets = instance ?: synchronized(this) {
            instance ?: SendspinSecrets(File(context.applicationContext.filesDir, "sendspin"))
                .also { instance = it }
        }
    }
}
