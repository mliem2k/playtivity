package com.mliem.playtivity.nativeapp

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SingleFlightTest {
    @Test fun concurrentCallsForTheSameKeyRunTheLoaderOnce() = runTest {
        val flight = SingleFlight<String, String>()
        var loads = 0
        val gate = CompletableDeferred<Unit>()
        val first = async { flight.run("key") { loads++; gate.await(); "shared" } }
        runCurrent()
        val second = async { flight.run("key") { loads++; "own" } }
        runCurrent()
        gate.complete(Unit)
        assertEquals("shared", first.await())
        assertEquals("shared", second.await())
        assertEquals(1, loads)
    }

    @Test fun differentKeysRunTheLoaderSeparately() = runTest {
        val flight = SingleFlight<String, String>()
        var loads = 0
        val first = async { flight.run("first") { loads++; "one" } }
        val second = async { flight.run("second") { loads++; "two" } }
        assertEquals("one", first.await())
        assertEquals("two", second.await())
        assertEquals(2, loads)
    }

    @Test fun failureRemovesTheEntrySoTheNextCallRetries() = runTest {
        val flight = SingleFlight<String, Int>()
        var loads = 0
        val failure = runCatching { flight.run("key") { loads++; throw IllegalStateException("boom") } }
        assertTrue(failure.exceptionOrNull() is IllegalStateException)
        assertEquals("boom", failure.exceptionOrNull()?.message)
        assertEquals(1, loads)

        assertEquals(7, flight.run("key") { loads++; 7 })
        assertEquals(2, loads)
    }

    @Test fun cancelledLeaderDoesNotCancelAnotherWaiter() = runTest {
        val flight = SingleFlight<String, String>()
        var loads = 0
        val started = CompletableDeferred<Unit>()
        val leader = launch {
            flight.run("key") {
                loads++
                started.complete(Unit)
                awaitCancellation()
            }
        }
        started.await()
        val waiter = async { flight.run("key") { loads++; "retried" } }
        runCurrent()

        leader.cancel()
        leader.join()

        assertEquals("retried", waiter.await())
        assertEquals(2, loads)
    }

    @Test fun cancelledLoadDoesNotPoisonTheKey() = runTest {
        val flight = SingleFlight<String, Int>()
        var loads = 0
        val started = CompletableDeferred<Unit>()
        val leader = launch {
            flight.run("key") {
                loads++
                started.complete(Unit)
                awaitCancellation()
            }
        }
        started.await()
        assertEquals(1, loads)
        leader.cancel()
        leader.join()

        assertEquals(7, flight.run("key") { loads++; 7 })
        assertEquals(2, loads)
    }
}
