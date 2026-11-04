// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import java.io.File

/** Only unique, direct cache children may replace the normal save root in QA. */
internal object ValidationSaves {
    fun resolve(cache:File,requested:File):File {
        val root=File(cache.canonicalFile,"validation-saves")
        require(root.canonicalFile==root){"Validation root must not be redirected"}
        val path=requested.absoluteFile
        require(path.parentFile==File(cache.absoluteFile,"validation-saves") && path.name.matches(Regex("run-[a-zA-Z0-9-]{8,80}"))){"Expected a unique validation cache child"}
        val canonical=File(root,path.name)
        require(path.canonicalFile==canonical){"Validation saves must not follow links"}
        return canonical
    }
}
