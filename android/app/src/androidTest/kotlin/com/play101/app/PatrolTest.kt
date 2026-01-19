package com.play101.app

import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import pl.leancode.patrol.PatrolJUnitRunner

class PatrolTest {
    @Test
    fun runPatrolTest() {
        val appContext = InstrumentationRegistry.getInstrumentation().targetContext
        PatrolJUnitRunner().runDartTest(appContext)
    }
}
