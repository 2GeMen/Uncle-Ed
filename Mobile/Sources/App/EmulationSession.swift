import UIKit
import AVFAudio

final class EmulationSession: NSObject {
    var onFrame: ((CGImage)->Void)?
    var onError: ((String)->Void)?
    private(set) var running=false
    var volume:Float=1 {didSet{emu_volume(volume)}}
    private var suspended=false
    var performanceStage=""
    private var performanceModel="",performanceTitle=""
    private var performanceHistory=[[String:Any]](),readbackStart:Double=0,conversionStart:Double=0
    private var lastVideoSerial:UInt=0,perfCallbacks=0,perfMaxBatch=0,perfDeadlineYields=0
    private var perfStart:CFTimeInterval=0,perfCore:Double=0,perfCopy:Double=0,perfFrames=0,perfTicks=0,perfWorst:Double=0
    private func recordPerformance(_ now:CFTimeInterval){
        guard now-perfStart>=10,perfCallbacks>0 else{return}
        let report:[String:Any]=["elapsedSeconds":now-perfStart,"emulatedFPS":Double(perfFrames)/(now-perfStart),"meanCoreMilliseconds":perfCore/Double(max(1,perfFrames))*1000,"meanFrameCopyMilliseconds":perfCopy/Double(max(1,perfTicks))*1000,"worstTickMilliseconds":perfWorst*1000,"thermalState":ProcessInfo.processInfo.thermalState.rawValue,"model":performanceModel,"cpuOption":performanceModel=="psp" ? String(cString:emu_core_option("ppsspp_cpu_core")):"core default","coreName":String(cString:emu_core_name()),"audioUnderrunSamples":emu_audio_underruns(),"audioBufferedSamples":emu_audio_buffered(),"coreVersion":String(cString:emu_core_version()),"game":performanceTitle,"stage":performanceStage,"requestedFPS":emu_fps(),"lowPowerMode":ProcessInfo.processInfo.isLowPowerModeEnabled,"presentationTarget":[emu_presentation_width(),emu_presentation_height()],"presentedFPS":Double(perfTicks)/(now-perfStart),"hostCallbacksPerSecond":Double(perfCallbacks)/(now-perfStart),"maxBatchFrames":perfMaxBatch,"deadlineYields":perfDeadlineYields,"gpuReadbackMilliseconds":(emu_readback_seconds()-readbackStart)/Double(max(1,perfFrames))*1000,"pixelConversionMilliseconds":(emu_conversion_seconds()-conversionStart)/Double(max(1,perfFrames))*1000,"timestamp":Date().timeIntervalSince1970]
        if let root=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask).first,let data=try? JSONSerialization.data(withJSONObject:report,options:.prettyPrinted){try? data.write(to:root.appendingPathComponent("performance.json"),options:.atomic)
            performanceHistory.append(report);if performanceHistory.count>120{performanceHistory.removeFirst()};if let history=try? JSONSerialization.data(withJSONObject:performanceHistory,options:.prettyPrinted){try? history.write(to:root.appendingPathComponent("performance-history.json"),options:.atomic)}}
        readbackStart=emu_readback_seconds();conversionStart=emu_conversion_seconds();perfCallbacks=0;perfMaxBatch=0;perfDeadlineYields=0;perfStart=now;perfCore=0;perfCopy=0;perfFrames=0;perfTicks=0;perfWorst=0
    }
    private var displayLink:CADisplayLink?
    private var previousTime:CFTimeInterval=0, accumulator:Double=0, saveTime:CFTimeInterval=0
    func start(_ item:ROMItem,library:ROMLibrary) throws {
        guard DeviceModel.available(onPhone:UIDevice.current.userInterfaceIdiom == .phone).contains(item.model) else{throw LibraryError.unavailable("iPhone 首批支持 GBA、GBC 和 PSP。")}
        stop()
        guard item.model != .n3ds else {throw LibraryError.unavailable("3DS 的 iPad 图形后端仍在移植中。ROM 可以先导入收藏，暂不启动。")}
        guard let core=Bundle.main.url(forResource:item.model.coreName,withExtension:"dylib",subdirectory:"cores") else {throw LibraryError.unavailable("此构建未包含该设备的模拟核心。请使用已内嵌签名核心的真机版本。")}
        let isolated=ProcessInfo.processInfo.arguments.contains("--profile-isolated-saves")
        let save=isolated ? library.root.appendingPathComponent("Diagnostics/"+UUID().uuidString+"/"+item.model.rawValue,isDirectory:true):library.root.appendingPathComponent("Saves/"+item.model.rawValue,isDirectory:true);try FileManager.default.createDirectory(at:save,withIntermediateDirectories:true)
        if item.model == .psp,let assets=Bundle.main.url(forResource:"Assets",withExtension:nil)?.appendingPathComponent("Systems/psp/PPSSPP") {
            let destination=save.appendingPathComponent("PPSSPP");if !FileManager.default.fileExists(atPath:destination.path){try FileManager.default.copyItem(at:assets,to:destination)}
        }
        try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default)
        try AVAudioSession.sharedInstance().setActive(true)
        #if DEBUG
        emu_diagnostic_legacy(ProcessInfo.processInfo.arguments.contains("--profile-legacy-cpu-value") ? 1:0,ProcessInfo.processInfo.arguments.contains("--profile-legacy-target") ? 1:0)
        #endif
        guard emu_start(core.path,library.romURL(item).path,save.path) != 0 else {throw LibraryError.unavailable(String(cString:emu_error()))}
        lastVideoSerial=0;perfCallbacks=0;perfMaxBatch=0;perfDeadlineYields=0;performanceModel=item.model.rawValue;performanceTitle=item.title;performanceHistory=[];readbackStart=emu_readback_seconds();conversionStart=emu_conversion_seconds();perfStart=CACurrentMediaTime();perfCore=0;perfCopy=0;perfFrames=0;perfTicks=0;perfWorst=0;running=true;UIApplication.shared.isIdleTimerDisabled=true;resume()
    }
    func resume(){guard running else{return};suspended=false;previousTime=0;accumulator=0;saveTime=CACurrentMediaTime();displayLink?.invalidate();let link=CADisplayLink(target:self,selector:#selector(tick(_:)));link.preferredFrameRateRange=CAFrameRateRange(minimum:30,maximum:60,preferred:60);link.add(to:.main,forMode:.common);displayLink=link;emu_volume(volume)}
    func pause(){guard running else{return};suspended=true;displayLink?.invalidate();displayLink=nil;releaseInputs();_ = emu_save();emu_volume(0)}
    func stop(){displayLink?.invalidate();displayLink=nil;releaseInputs();if running{_ = emu_save();emu_stop()};running=false;suspended=false;UIApplication.shared.isIdleTimerDisabled=false}
    func instantState(restore:Bool,slot:Int)->Int32 {
        guard running else{return 0};let wasSuspended=suspended;pause();releaseInputs()
        let result=restore ? emu_state_load(Int32(slot)):emu_state_save(Int32(slot))
        previousTime=0;accumulator=0;lastVideoSerial=0
        if result == -2{stop()}else if !wasSuspended{resume()};return result
    }
    func releaseInputs(){for id in 0..<16 {emu_button(Int32(id),0)};emu_touch(0,0,0);emu_axis(0,0,0);emu_axis(0,1,0)}
    @objc private func tick(_ link:CADisplayLink){
        guard running,!suspended else{return}
        if previousTime==0 {previousTime=link.timestamp;return}
        accumulator += min(0.1,link.timestamp-previousTime);previousTime=link.timestamp
        let tickStart=CACurrentMediaTime();let step=1/max(1,emu_fps());var count=0
        var yielded=false
        while accumulator>=step && count<4 {
            emu_run();accumulator-=step;count+=1
            // A slow core must not monopolise the main thread for four frames.
            // Every core frame still runs; only the catch-up batch yields sooner.
            if CACurrentMediaTime()-tickStart>=min(step,1.0/60)*0.75 {yielded=true;break}
        }
        if yielded{perfDeadlineYields+=1};perfMaxBatch=max(perfMaxBatch,count);perfCallbacks+=1
        perfCore += CACurrentMediaTime()-tickStart;perfFrames += count
        if count==4 || yielded {accumulator=min(accumulator,step)}
        if link.timestamp-saveTime>10 {_ = emu_save();saveTime=link.timestamp}
        guard count>0 else{return}
        let serial=emu_video_serial()
        guard serial != lastVideoSerial else{perfWorst=max(perfWorst,CACurrentMediaTime()-tickStart);recordPerformance(CACurrentMediaTime());return}
        lastVideoSerial=serial
        let copyStart=CACurrentMediaTime()
        let width=Int(emu_width()),height=Int(emu_height());guard width>0,height>0,width<=2048,height<=2048,let pixels=emu_pixels() else{return}
        let data=Data(bytes:pixels,count:width*height*4)
        guard let provider=CGDataProvider(data:data as CFData),let image=CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else{return}
        onFrame?(image)
        perfCopy += CACurrentMediaTime()-copyStart;perfTicks+=1;perfWorst=max(perfWorst,CACurrentMediaTime()-tickStart);recordPerformance(CACurrentMediaTime())
    }
    deinit{displayLink?.invalidate()}
}
