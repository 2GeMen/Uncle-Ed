import CoreGraphics
import XCTest
import ZIPFoundation
import CryptoKit
@testable import UncleEdDomain
final class MobileDomainTests:XCTestCase {
    func testPickerFlickAdvancesAndMomentumCannotSkipNeighbours(){
        XCTAssertEqual(PickerMotion.snappedIndex(position:0.12,velocity:0.7,start:0,count:5),1)
        XCTAssertEqual(PickerMotion.snappedIndex(position:2.85,velocity:-0.7,start:3,count:5),2)
        XCTAssertEqual(PickerMotion.snappedIndex(position:20,velocity:8,start:1,count:5),2)
        XCTAssertEqual(PickerMotion.snappedIndex(position:-20,velocity:-8,start:1,count:5),0)
        XCTAssertEqual(PickerMotion.snappedIndex(position:0.1,velocity:0,start:0,count:5),0)
        XCTAssertEqual(PickerMotion.trackpadPosition(current:2,delta:-1000,anchor:2,count:5),3)
        XCTAssertEqual(PickerMotion.trackpadPosition(current:2,delta:1000,anchor:2,count:5),1)
        XCTAssertEqual(PickerMotion.trackpadPosition(current:0,delta:90,anchor:0,count:5),0)
        XCTAssertEqual(PickerMotion.trackpadPosition(current:1,delta:-45,anchor:1,count:5),1.25)
    }
    func testGBAControlsClearEnlargedScreenSurround() {
        let g=DeviceGeometry.make(.gba)
        let bezel=CGRect(x:176,y:50,width:368,height:268)
        let pad=[GameControl.up,.down,.left,.right].compactMap{g.controls[$0]}.reduce(CGRect.null){$0.union($1)}
        XCTAssertGreaterThanOrEqual(bezel.minX-pad.maxX,18)
        XCTAssertGreaterThanOrEqual(g.controls[.b]!.minX-bezel.maxX,24)
        XCTAssertEqual(g.controls[.a]!.midX-g.controls[.b]!.midX,44)
        XCTAssertEqual(g.controls[.b]!.midY-g.controls[.a]!.midY,40)
        for size in [CGSize(width:956,height:440),CGSize(width:1180,height:820)] {
            let layout=MobileLayout(model:.gba,viewport:size,topInset:0,bottomInset:20,nativePhone:size.width<1000,immersiveWidePad:size.width>1000)
            for key in [GameControl.up,.down,.left,.right,.a,.b] {
                let r=layout.rect(g.controls[key]!);XCTAssertEqual(layout.control(at:CGPoint(x:r.midX,y:r.midY)),key)
            }
        }
    }
    func testPadLandscapeWideMachinesUseShellBounds() {
        for model in [DeviceModel.gba,.psp] {
            let l=MobileLayout(model:model,viewport:CGSize(width:1180,height:820),topInset:24,bottomInset:20,immersiveWidePad:true)
            let shell=CGRect(x:28,y:model == .psp ? 18:12,width:664,height:model == .psp ? 306:350)
            let physical=l.rect(shell)
            XCTAssertGreaterThan(physical.width,1140)
            XCTAssertGreaterThanOrEqual(physical.minX,13.9)
            XCTAssertLessThanOrEqual(physical.maxX,1166.1)
            XCTAssertGreaterThanOrEqual(physical.minY,38)
            XCTAssertLessThanOrEqual(physical.maxY,786.1)
            for (key,r) in l.geometry.controls {
                XCTAssertEqual(l.control(at:CGPoint(x:l.rect(r).midX,y:l.rect(r).midY)),key)
            }
        }
    }
    func testPSPLCDUsesOriginalFaceRatioWithoutOverlappingControls(){
        let g=DeviceGeometry.make(.psp),lcd=g.screens[0],body=g.shells[0]
        XCTAssertGreaterThan(lcd.width/body.width,0.60)
        XCTAssertEqual(lcd.width/lcd.height,480.0/272.0,accuracy:0.0001)
        XCTAssertLessThan(lcd.maxX,g.controls[.y]!.minX)
        XCTAssertGreaterThan(lcd.minX,g.controls[.right]!.maxX)
    }
    func testAirLayoutsFitSafeAreaAndPreserveAspect(){
        for size in [CGSize(width:820,height:1180),CGSize(width:1180,height:820),CGSize(width:1024,height:1366),CGSize(width:1366,height:1024)] {
            for model in DeviceModel.allCases {
                let l=MobileLayout(model:model,viewport:size,topInset:24,bottomInset:20)
                XCTAssertGreaterThanOrEqual(l.frame.minX,20);XCTAssertLessThanOrEqual(l.frame.maxX,size.width-19)
                XCTAssertGreaterThanOrEqual(l.frame.minY,88);XCTAssertLessThanOrEqual(l.frame.maxY,size.height-19)
                XCTAssertEqual(l.frame.width/l.frame.height,l.geometry.size.width/l.geometry.size.height,accuracy:0.0001)
                for (control,r) in l.geometry.controls {let point=CGPoint(x:l.rect(r).midX,y:l.rect(r).midY);XCTAssertEqual(l.control(at:point),control,"\(model) \(control)")}
            }
        }
    }
    func testMultitouchDoesNotReleaseOtherFinger(){var state=MultiTouchButtons();XCTAssertEqual(state.update(finger:1,control:.a).count,1);XCTAssertTrue(state.update(finger:2,control:.a).isEmpty);XCTAssertTrue(state.update(finger:1,control:nil).isEmpty);let released=state.update(finger:2,control:nil);XCTAssertEqual(released.first?.0,.a);XCTAssertEqual(released.first?.1,false)}
    func testDirectionAndActionCanBeHeldTogether(){var state=MultiTouchButtons();_ = state.update(finger:1,control:.left);_ = state.update(finger:2,control:.a);XCTAssertEqual(state.releaseAll().count,2);XCTAssertTrue(state.releaseAll().isEmpty)}
    func testArchivePaths(){for name in ["../bad.gba","/bad.nds","a/../../bad.gbc","a\\bad.gba","C:/bad.gba"]{XCTAssertFalse(safeArchivePath(name))};XCTAssertTrue(safeArchivePath("Games/Pokemon.gba"))}
    func testCoverMatchingPreservesNumberedTitles(){XCTAssertNotEqual(coverMatchKey("Super Mario Bros. 3"),coverMatchKey("Super Mario Bros. 4"));XCTAssertEqual(coverMatchKey("Pokemon - FireRed Version (USA).gba"),coverMatchKey("Pokemon - FireRed Version (USA)"))}
    func testCoreRouting(){XCTAssertEqual(DeviceModel.detect(extension:"GBA"),.gba);XCTAssertEqual(DeviceModel.gba.coreName,DeviceModel.gbc.coreName);XCTAssertNil(DeviceModel.detect(extension:"png"));XCTAssertNil(DeviceModel.gbc.themes.firstIndex(of:"L/R"))}
    func testROMAndZIPImportDeduplicateActualContent()throws{
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)}
        let rom=folder.appendingPathComponent("Example (USA).gba");try Data(repeating:0x42,count:1024).write(to:rom);let archive=folder.appendingPathComponent("Example.zip");try FileManager.default.zipItem(at:rom,to:archive)
        let library=ROMLibrary(root:folder.appendingPathComponent("Library"));let completed=expectation(description:"import")
        library.importFiles([rom,archive]){summary in XCTAssertEqual(summary.added.count,1);XCTAssertEqual(summary.duplicateCount,1);XCTAssertTrue(summary.failures.isEmpty);let item=library.load().first!;XCTAssertEqual(item.title,"Example");XCTAssertEqual(try? Data(contentsOf:library.romURL(item)),Data(repeating:0x42,count:1024));XCTAssertTrue(FileManager.default.fileExists(atPath:rom.path));completed.fulfill()};wait(for:[completed],timeout:10)
    }
    func testEmptyImportIsRejected()throws{let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:folder)};let rom=folder.appendingPathComponent("empty.gbc");try Data().write(to:rom);let library=ROMLibrary(root:folder.appendingPathComponent("Library"));let done=expectation(description:"empty rejected");library.importFiles([rom]){summary in XCTAssertTrue(summary.added.isEmpty);XCTAssertEqual(summary.failures.count,1);done.fulfill()};wait(for:[done],timeout:10)}
    func testLargeROMStreamingAndRecovery() throws {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer{try? FileManager.default.removeItem(at:folder)}
        let rom=folder.appendingPathComponent("Large.cci")
        FileManager.default.createFile(atPath:rom.path,contents:nil)
        let handle=try FileHandle(forWritingTo:rom);try handle.truncate(atOffset:268435456);try handle.close()
        let library=ROMLibrary(root:folder.appendingPathComponent("Library")),done=expectation(description:"large streamed import")
        library.importFiles([rom]){summary in
            XCTAssertEqual(summary.added.count,1);XCTAssertTrue(summary.failures.isEmpty)
            if let item=summary.added.first {
                XCTAssertEqual((try? FileManager.default.attributesOfItem(atPath:library.romURL(item).path)[.size] as? NSNumber)?.uint64Value,268435456)
                var hash=SHA256();let block=Data(repeating:0,count:1048576);for _ in 0..<256 {hash.update(data:block)}
                XCTAssertEqual(item.id,hash.finalize().map{String(format:"%02x",$0)}.joined())
            }
            done.fulfill()
        };wait(for:[done],timeout:60)
        let orphan=library.root.appendingPathComponent("Staging/"+UUID().uuidString)
        try Data([1]).write(to:orphan);_ = ROMLibrary(root:library.root)
        XCTAssertFalse(FileManager.default.fileExists(atPath:orphan.path));XCTAssertEqual(library.load().count,1)
    }

    func testEveryModelControlRoutesAndReleases(){
        for model in DeviceModel.allCases {let g=DeviceGeometry.make(model)
            for (control,r) in g.controls {var router=TouchInputRouter();let point=CGPoint(x:r.midX,y:r.midY)
                XCTAssertTrue(router.update(finger:1,point:point,ending:false,geometry:g,enabled:true,scale:1).contains(.button(control,true)),"\(model) \(control)")
                XCTAssertTrue(router.update(finger:1,point:point,ending:true,geometry:g,enabled:true,scale:1).contains(.button(control,false)))
            }
        }
    }
    func testStickAndFaceMultitouch(){
        let g=DeviceGeometry.make(.psp),r=g.stick!,a=g.controls[.a]!;var router=TouchInputRouter()
        _=router.update(finger:1,point:CGPoint(x:r.midX,y:r.midY),ending:false,geometry:g,enabled:true,scale:1)
        let axis=router.update(finger:1,point:CGPoint(x:r.maxX,y:r.maxY),ending:false,geometry:g,enabled:true,scale:1)
        XCTAssertTrue(axis.contains{if case .axis(let x,let y)=$0{return x>0.7 && y>0.7 && hypot(x,y)<=1.001};return false})
        XCTAssertTrue(router.update(finger:2,point:CGPoint(x:a.midX,y:a.midY),ending:false,geometry:g,enabled:true,scale:1).contains(.button(.a,true)))
        XCTAssertEqual(router.update(finger:1,point:.zero,ending:true,geometry:g,enabled:true,scale:1),[.axis(0,0)])
        XCTAssertTrue(router.releaseAll().contains(.button(.a,false)))
    }
    func testDiagonalAndTwoFingersOnOneDirection(){
        let g=DeviceGeometry.make(.gba),up=g.controls[.up]!,right=g.controls[.right]!;var router=TouchInputRouter();let point=CGPoint(x:right.midX,y:up.midY)
        let down=router.update(finger:1,point:point,ending:false,geometry:g,enabled:true,scale:1)
        XCTAssertTrue(down.contains(.button(.up,true)));XCTAssertTrue(down.contains(.button(.right,true)))
        _=router.update(finger:2,point:point,ending:false,geometry:g,enabled:true,scale:1)
        XCTAssertTrue(router.update(finger:1,point:.zero,ending:true,geometry:g,enabled:true,scale:1).isEmpty)
        let upEvents=router.releaseAll();XCTAssertTrue(upEvents.contains(.button(.up,false)));XCTAssertTrue(upEvents.contains(.button(.right,false)))
    }
    func testScreenAndFaceMultitouch(){
        let g=DeviceGeometry.make(.nds),r=g.screens[1],a=g.controls[.a]!;var router=TouchInputRouter()
        let events=router.update(finger:1,point:CGPoint(x:r.midX,y:r.midY),ending:false,geometry:g,enabled:true,scale:1)
        guard case let .pointer(x,y,true)?=events.first else{return XCTFail("Screen centre must route to touch input")}
        XCTAssertEqual(x,0.5,accuracy:0.000001);XCTAssertEqual(y,0.5,accuracy:0.000001)
        XCTAssertTrue(router.update(finger:2,point:CGPoint(x:a.midX,y:a.midY),ending:false,geometry:g,enabled:true,scale:1).contains(.button(.a,true)))
        XCTAssertTrue(router.update(finger:1,point:.zero,ending:true,geometry:g,enabled:true,scale:1).contains(.pointer(0,0,false)))
        XCTAssertTrue(router.releaseAll().contains(.button(.a,false)))
    }
    func testBookAndShelfFitAir(){for size in [CGSize(width:820,height:1180),CGSize(width:1180,height:820)] {
        let book=MobileLayout(model:.nds,viewport:size,topInset:24,bottomInset:20,rotated:true)
        XCTAssertLessThanOrEqual(book.frame.maxX,size.width-20);XCTAssertLessThanOrEqual(book.frame.maxY,size.height-20)
        for model in DeviceModel.allCases{let shelf=MobileLayout(model:model,viewport:size,topInset:264,bottomInset:20);XCTAssertGreaterThanOrEqual(shelf.frame.minY,328);XCTAssertLessThanOrEqual(shelf.frame.maxY,size.height-20)}
    }}

    func testVerticalPositionLimitsAlwaysKeepWholeMachineVisible(){
        for viewport in [CGSize(width:820,height:1180),CGSize(width:1180,height:820),CGSize(width:393,height:852),CGSize(width:852,height:393)] {
            for model in DeviceModel.allCases {for value in [CGFloat(-1),0,0.58,0.86,1,2] {for rotated in [false,true] {
                let l=MobileLayout(model:model,viewport:viewport,topInset:24,bottomInset:20,rotated:rotated,verticalPosition:value)
                XCTAssertGreaterThanOrEqual(l.frame.minY,88);XCTAssertLessThanOrEqual(l.frame.maxY,viewport.height-20)
                XCTAssertGreaterThanOrEqual(l.frame.minX,20);XCTAssertLessThanOrEqual(l.frame.maxX,viewport.width-20)
            }}}
        }
    }

    func testMacLidProjectionClosedAndOpen(){
        let closed=LidProjection(openness:0),open=LidProjection(openness:1)
        XCTAssertFalse(closed.inner);XCTAssertEqual(closed.farY,690,accuracy:0.001)
        XCTAssertEqual(closed.farWidth,640,accuracy:0.001)
        XCTAssertTrue(open.inner);XCTAssertLessThan(open.farY,30)
        for value in stride(from:CGFloat(0),through:1,by:0.01){let p=LidProjection(openness:value);XCTAssertTrue(p.farY.isFinite);XCTAssertTrue(p.farWidth.isFinite);XCTAssertGreaterThanOrEqual(p.farWidth,640)}
    }

    func testSharedCartridgeSlotGeometry(){
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data=try! Data(contentsOf:root.appendingPathComponent("Assets/media-slots.json"))
        let mac=root.deletingLastPathComponent().appendingPathComponent("uncleed/Assets/media-slots.json")
        XCTAssertEqual(data,try! Data(contentsOf:mac))
        let specs=try! JSONDecoder().decode([String:CartridgeSlot].self,from:data)
        for (model,spec) in specs {XCTAssertGreaterThan(spec.width,spec.cardWidth,model);XCTAssertLessThanOrEqual(spec.width-spec.cardWidth,8,model);XCTAssertGreaterThan(spec.ratio,0)}
        XCTAssertEqual(specs["gba"]!.cardWidth,256);XCTAssertGreaterThan(specs["gba"]!.cardWidth,specs["nds"]!.cardWidth)
    }

    func testPhoneModelsRespectNativeShape(){
        XCTAssertEqual(DeviceModel.available(onPhone:true),[.gba,.gbc,.psp])
        XCTAssertEqual(DeviceModel.available(onPhone:false),DeviceModel.allCases)
        XCTAssertNil(DeviceGeometry.make(.gbc).controls[.l]);XCTAssertNil(DeviceGeometry.make(.gbc).controls[.r])
    }
    func testNativePhoneSafeAreaAndControlCoordinates(){
        for model in DeviceModel.available(onPhone:true) {
            let portrait=model == .gbc,size=portrait ? CGSize(width:440,height:956):CGSize(width:956,height:440)
            let top:CGFloat=portrait ? 62:0,bottom:CGFloat=portrait ? 34:21,side:CGFloat=portrait ? 0:62
            let visible=portrait ? CGRect(x:8,y:10,width:370,height:600):model == .psp ? CGRect(x:28,y:20,width:664,height:304):CGRect(x:30,y:14,width:660,height:348)
            for zoom in [CGFloat(0.55),0.8,1,2] {for x in [CGFloat(0),0.5,1] {for y in [CGFloat(0),0.5,1] {
                let l=MobileLayout(model:model,viewport:size,topInset:top,bottomInset:bottom,verticalPosition:y,zoom:zoom,horizontalPosition:x,nativePhone:true,leftInset:side,rightInset:side)
                let r=l.rect(visible)
                XCTAssertGreaterThanOrEqual(r.minX,3.99);XCTAssertLessThanOrEqual(r.maxX,size.width-3.99)
                XCTAssertGreaterThanOrEqual(r.minY,top+3.99);XCTAssertLessThanOrEqual(r.maxY,size.height-bottom-3.99)
                XCTAssertEqual(l.frame.width/l.frame.height,l.geometry.size.width/l.geometry.size.height,accuracy:0.0001)
                for (control,local) in l.geometry.controls {
                    XCTAssertGreaterThanOrEqual(l.rect(local).minX,side+3.99);XCTAssertLessThanOrEqual(l.rect(local).maxX,size.width-side-3.99)
                    let point=CGPoint(x:l.rect(local).midX,y:l.rect(local).midY),back=l.local(point)
                    XCTAssertEqual(back.x,local.midX,accuracy:0.001);XCTAssertEqual(back.y,local.midY,accuracy:0.001)
                    var router=TouchInputRouter()
                    XCTAssertTrue(router.update(finger:1,point:back,ending:false,geometry:l.geometry,enabled:true,scale:l.scale).contains(.button(control,true)),"\(model) \(control)")
                    _=router.releaseAll()
                }
            }}}
        }
    }

}

final class MechanicalDPadTests:XCTestCase {
    func testRigidCrossTiltsTowardEachPressedEdge(){
        XCTAssertLessThan(DPadPose(held:[.up]).x,0)
        XCTAssertGreaterThan(DPadPose(held:[.down]).x,0)
        XCTAssertLessThan(DPadPose(held:[.left]).y,0)
        XCTAssertGreaterThan(DPadPose(held:[.right]).y,0)
        let diagonal=DPadPose(held:[.up,.right])
        XCTAssertEqual(hypot(diagonal.x,diagonal.y),0.14,accuracy:0.000001)
        XCTAssertLessThan(diagonal.x,0);XCTAssertGreaterThan(diagonal.y,0)
    }
    func testOpposingDirectionsCancelWithoutAffectingOtherAxis(){
        let neutral=DPadPose(held:[.up,.down,.left,.right])
        XCTAssertEqual(neutral.x,0);XCTAssertEqual(neutral.y,0)
        let right=DPadPose(held:[.up,.down,.right])
        XCTAssertEqual(right.x,0);XCTAssertEqual(right.y,0.14,accuracy:0.000001)
        XCTAssertEqual(DPadPose(held:[.a,.b]).x,0)
        XCTAssertEqual(DPadPose(held:[]).y,0)
    }
    func testDiscLoadingHasOrderedPhysicalPhases(){
        XCTAssertGreaterThan(MediaLoadingMotion.duration("psp"),2.5)
        XCTAssertEqual(MediaLoadingMotion.doorAngle(0),0)
        XCTAssertEqual(MediaLoadingMotion.doorAngle(0.20),1.18,accuracy:0.00001)
        XCTAssertEqual(MediaLoadingMotion.doorAngle(0.65),1.18,accuracy:0.00001)
        XCTAssertEqual(MediaLoadingMotion.doorAngle(0.85),0,accuracy:0.00001)
        XCTAssertEqual(MediaLoadingMotion.spinAngle(0.85),0)
        XCTAssertGreaterThan(MediaLoadingMotion.spinAngle(1),10 * .pi)
        XCTAssertEqual(MediaLoadingMotion.soundEvents("psp",1),["psp-door-open","psp-disc-seat","psp-door-close","psp-disc-read"])
        XCTAssertFalse(MediaLoadingMotion.soundEvents("psp",0.65).contains("psp-door-close"))
    }
    func testPSPPanelClearances(){
        let g=DeviceGeometry.make(.psp),lcd=g.screens[0]
        for key in [GameControl.y,.b,.a,.x]{XCTAssertGreaterThan(g.controls[key]!.minX-lcd.maxX,16)}
        for key in [GameControl.select,.start]{XCTAssertGreaterThan(g.controls[key]!.minY-lcd.maxY,12)}
        XCTAssertLessThan(g.controls[.l]!.maxX,lcd.minX)
        XCTAssertGreaterThan(g.controls[.r]!.minX,lcd.maxX)
    }

}
