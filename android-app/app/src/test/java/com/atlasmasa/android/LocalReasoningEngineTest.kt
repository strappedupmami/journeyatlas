package com.atlasmasa.android

import com.atlasmasa.android.domain.LocalReasoningEngine
import com.atlasmasa.android.domain.UserNote
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class LocalReasoningEngineTest {
    private val engine = LocalReasoningEngine()

    @Test
    fun `detects emergency intent`() {
        val result = engine.reason("Emergency: bleeding after fall", emptyList())
        assertTrue(result.confidence >= 0.9)
        assertTrue(result.summary.lowercase().contains("emergency"))
    }

    @Test
    fun `detects wealth route intent`() {
        val result = engine.reason("Need higher income and job promotion plan", emptyList())
        assertTrue(result.confidence >= 0.85)
        assertTrue(result.summary.lowercase().contains("wealth") || result.summary.lowercase().contains("growth"))
    }

    @Test
    fun `includes context notes for default route`() {
        val result = engine.reason("I need a weekly execution plan", listOf(UserNote(title = "n", content = "ctx")))
        assertTrue(result.confidence > 0.5)
        assertTrue(result.nextAction.isNotBlank())
    }

    @Test
    fun `handles empty prompt safely`() {
        val result = engine.reason("   ", emptyList())
        assertEquals(0.0, result.confidence, 0.0001)
        assertTrue(result.nextAction.isNotBlank())
    }

    @Test
    fun `handles hebrew emergency intent`() {
        val result = engine.reason("מצב חירום עם דימום אחרי נפילה", emptyList())
        assertTrue(result.confidence >= 0.9)
        assertTrue(result.summary.contains("חירום"))
    }
}
