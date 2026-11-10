package com.mliem.playtivity.nativeapp

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

/**
 * Runs at most one [loader] per key at a time: concurrent callers for the same key await one result.
 * A failed or cancelled load is forgotten, so a later call retries instead of observing the failure forever.
 * A caller whose own coroutine is cancelled stops waiting; if only the shared load was cancelled, the
 * remaining callers retry as the new leader.
 */
internal class SingleFlight<K, V> {
    private val flights = HashMap<K, Deferred<V>>()

    suspend fun run(key: K, loader: suspend () -> V): V {
        while (true) {
            val shared = CompletableDeferred<V>()
            val existing = synchronized(flights) {
                flights[key] ?: run { flights[key] = shared; null }
            }
            if (existing != null) {
                try {
                    return existing.await()
                } catch (_: CancellationException) {
                    // Our own cancellation must propagate; a cancelled shared load is retried below.
                    currentCoroutineContext().ensureActive()
                    continue
                }
            }
            try {
                val value = loader()
                shared.complete(value)
                return value
            } catch (error: Throwable) {
                remove(key, shared)
                shared.completeExceptionally(error)
                throw error
            } finally {
                remove(key, shared)
            }
        }
    }

    private fun remove(key: K, shared: Deferred<V>) {
        synchronized(flights) {
            if (flights[key] === shared) flights.remove(key)
        }
    }
}
