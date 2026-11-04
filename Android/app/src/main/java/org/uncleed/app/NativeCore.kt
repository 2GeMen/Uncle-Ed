package org.uncleed.app
import java.nio.ByteBuffer
object NativeCore {
 init { System.loadLibrary("uncleed") }
 external fun load(core:String,rom:String,system:String,save:String):Boolean
 external fun stateIdentity(romHash:String,coreHash:String)
 external fun stateOperation(restore:Boolean,slot:Int):Int
 external fun stateError():String
 external fun run()
 external fun flushSave():Boolean
 external fun saveError():String
 external fun stop()
 external fun input(mask:Int,x:Int,y:Int,touchX:Int,touchY:Int,down:Boolean)
 external fun timing():LongArray
 external fun info():IntArray
 external fun copyFrame(buffer:ByteBuffer,screen:Int,dual:Boolean):Int
 external fun pullAudio(buffer:ByteBuffer):Int
 external fun error():String
}
