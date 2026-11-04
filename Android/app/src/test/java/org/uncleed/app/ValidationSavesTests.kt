// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import java.io.File
import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class ValidationSavesTests {
    private fun fixture(test:(File)->Unit){val root=Files.createTempDirectory("uncleed-validation-").toFile();try{test(root.canonicalFile)}finally{root.deleteRecursively()}}
    private fun rejects(cache:File,path:File){try{ValidationSaves.resolve(cache,path);fail("Unsafe save override accepted")}catch(_:IllegalArgumentException){}}
    @Test fun acceptsOnlyUniqueDirectCacheChild()=fixture{cache->
        val path=File(cache,"validation-saves/run-12345678")
        assertEquals(path,ValidationSaves.resolve(cache,path))
        rejects(cache,File(cache,"validation-saves"))
        rejects(cache,File(cache,"validation-saves/run-short"))
        rejects(cache,File(cache,"validation-saves/run-12345678/nested"))
        rejects(cache,File(cache,"saves/run-12345678"))
        rejects(cache,File(cache,"validation-saves/../run-12345678"))
    }
    @Test fun acceptsSystemAliasForCache()=fixture{base->
        val cache=File(base,"real-cache").also{it.mkdirs()};val alias=File(base,"cache-alias")
        Files.createSymbolicLink(alias.toPath(),cache.toPath())
        assertEquals(File(cache,"validation-saves/run-12345678"),ValidationSaves.resolve(alias,File(alias,"validation-saves/run-12345678")))
    }
    @Test fun rejectsRedirectedRoot()=fixture{cache->
        val other=File(cache,"user-saves").also{it.mkdirs()}
        Files.createSymbolicLink(File(cache,"validation-saves").toPath(),other.toPath())
        rejects(cache,File(cache,"validation-saves/run-12345678"))
    }
    @Test fun rejectsRedirectedRun()=fixture{cache->
        val root=File(cache,"validation-saves").also{it.mkdirs()}
        val other=File(cache,"user-saves").also{it.mkdirs()}
        val path=File(root,"run-12345678")
        Files.createSymbolicLink(path.toPath(),other.toPath())
        rejects(cache,path)
    }
}
