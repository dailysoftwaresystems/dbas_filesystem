package com.example.dbas_filesystem

import kotlin.test.Test
import kotlin.test.assertNotNull

internal class DbasFilesystemPluginTest {
    @Test
    fun pluginCanBeInstantiated() {
        val plugin = DbasFilesystemPlugin()
        assertNotNull(plugin)
    }
}
