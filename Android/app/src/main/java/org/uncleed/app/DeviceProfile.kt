// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

import android.content.Context
import android.os.Build
import android.view.WindowManager
import kotlin.math.min

/** Device capability stays independent of a temporary split-screen window. */
object DeviceProfile {
    fun isTablet(context:Context):Boolean {
        if(Build.VERSION.SDK_INT>=30){
            val wm=context.getSystemService(WindowManager::class.java)
            val bounds=wm.maximumWindowMetrics.bounds
            val density=context.resources.displayMetrics.density
            return min(bounds.width(),bounds.height())/density>=600f
        }
        return context.resources.configuration.smallestScreenWidthDp>=600
    }
}
