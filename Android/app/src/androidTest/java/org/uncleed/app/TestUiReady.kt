// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app
import android.app.Instrumentation
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo

/** Normal first-launch system affordance, not a permission or a lockscreen bypass. */
fun dismissFirstRunFullscreenHint(probe:Instrumentation){
 val deadline=SystemClock.uptimeMillis()+3000
 while(SystemClock.uptimeMillis()<deadline){
  val root=probe.uiAutomation.rootInActiveWindow
  val button=listOf("Got it","知道了").firstNotNullOfOrNull{text->root?.findAccessibilityNodeInfosByText(text)?.firstOrNull()}
  if(button!=null){button.performAction(AccessibilityNodeInfo.ACTION_CLICK);SystemClock.sleep(350);return}
  SystemClock.sleep(100)
 }
}
