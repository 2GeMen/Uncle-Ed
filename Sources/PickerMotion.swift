import Foundation

/// Paging is bounded to the neighbouring item so trackpad momentum and a quick
/// phone flick cannot skip a machine. Position remains continuous during drag.
enum PickerMotion {
 static func trackpadPosition(current:CGFloat,delta:CGFloat,anchor:CGFloat,count:Int)->CGFloat {
  max(0,min(CGFloat(max(0,count-1)),max(anchor-1,min(anchor+1,current-delta/180))))
 }
 static func snappedIndex(position:CGFloat,velocity:CGFloat,start:Int,count:Int)->Int {
  let proposed=abs(velocity)>0.25 ? (velocity>0 ? floor(position)+1:ceil(position)-1):position.rounded()
  return Int(max(0,min(CGFloat(max(0,count-1)),max(CGFloat(start-1),min(CGFloat(start+1),proposed)))))
 }
}

/// Physical loading phases; the disc is seated before the door can close.
enum MediaLoadingMotion {
 static func duration(_ model:String)->Double{model=="psp" ? 2.95:1.65}
 static func ease(_ x:Double)->Double{let t=max(0,min(1,x));return t*t*t*(t*(t*6-15)+10)}
 static func doorAngle(_ t:Double)->Double{1.18*ease(t/0.18)*(1-ease((t-0.68)/0.16))}
 static func spinAngle(_ t:Double)->Double{let p=max(0,min(1,(t-0.86)/0.14));return 12 * Double.pi * p*p}
 static func soundEvents(_ model:String,_ t:Double)->[String]{
  let stages:[(Double,String)]=model=="psp" ? [(0,"psp-door-open"),(0.65,"psp-disc-seat"),(0.84,"psp-door-close"),(0.88,"psp-disc-read")]:[(0,"media-slide"),(0.85,"media-latch")]
  return stages.filter{t >= $0.0}.map{$0.1}
 }
}
