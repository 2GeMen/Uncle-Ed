// SPDX-License-Identifier: GPL-3.0-or-later
package org.uncleed.app

/** iOS uses each preview's own physical bounds inside its safe-area card. */
internal object PreviewFit {
 fun scale(halfWidth:Float,halfHeight:Float,aspect:Float,tablet:Boolean):Float {
  require(halfWidth>0&&halfHeight>0&&aspect>0)
  return minOf(aspect*(if(tablet).90f else .76f)/halfWidth,(if(tablet).80f else .84f)/halfHeight)
 }
}
