import AVFoundation

let processingQueue = DispatchQueue(label: "task", qos: .userInitiated, attributes: .concurrent)

class CompressionCancel {
    var cancel = false
}

enum AudioSampleRate: Int {
    //48000, 44100, 32000,24000, 22050, 16000, 12000, 11025, 8000
    case k48000 = 48000
    case k44100 = 44100
    case k32000 = 32000
    case k24000 = 24000
    case k22050 = 22050
    case k16000 = 16000
    case k12000 = 12000
    case k11025 = 11025
    case k8000 = 8000
}

struct CompressionConfig {
    let videoBitrate: Int
    let audioBitrate: Int
    let audioSampleRate: AudioSampleRate
    let videoMaxKeyFrameInterval: Int
    let avVideoProfileLevel: String
    let compressionResolution: (width: Int, height: Int)?
    
    static let defaultConfig = CompressionConfig(
        videoBitrate: 2 * 1024,
        audioBitrate: 80_000,
        audioSampleRate: .k44100,
        videoMaxKeyFrameInterval: 30,
        avVideoProfileLevel: AVVideoProfileLevelH264High41,
        compressionResolution: (width: 1280, height: 720)
    )
}

enum CompressionResult {
    case success(URL)
    case failure(Error)
    case cancelled
}

func compressVideo(_ urlToCompress: URL, _ outputURL: URL, _ compressionConfig: CompressionConfig, _ progressQueue: DispatchQueue, _ progressHandler: ((Progress) -> ())?, _ audioProgressHandler: ((Progress) -> ())?,  _ completeHandler: @escaping (CompressionResult) -> Void) -> CompressionCancel {
    
    let cancelable = CompressionCancel()
    
    let videoAsset = AVURLAsset(url: urlToCompress)
    guard let videoTrack = videoAsset.tracks(withMediaType: AVMediaType.video).first else {
        fatalError("Cannot find video track")
    }
    let audioTrack = videoAsset.tracks(withMediaType: AVMediaType.audio).first
    
    let durationInSeconds = videoAsset.duration.seconds
    let totalTime = Int64(floor(durationInSeconds))
    let videoProgress = Progress(totalUnitCount: totalTime)
    let audioProgress = Progress(totalUnitCount: totalTime)
    
    let size = compressionConfig.compressionResolution
    let videoCompressionProps: Dictionary<String, Any> = [
        AVVideoAverageBitRateKey : compressionConfig.videoBitrate,
        AVVideoMaxKeyFrameIntervalKey : compressionConfig.videoMaxKeyFrameInterval,
        AVVideoProfileLevelKey : compressionConfig.avVideoProfileLevel
    ]
    let videoOutputSettings: [String : Any] = [
        AVVideoCompressionPropertiesKey : videoCompressionProps,
        AVVideoCodecKey : AVVideoCodecType.h264,
        AVVideoWidthKey : size?.width ?? videoTrack.naturalSize.width,
        AVVideoHeightKey : size?.height ?? videoTrack.naturalSize.height
    ]
    
    let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: videoOutputSettings)
    videoWriterInput.expectsMediaDataInRealTime = true//TODO
    videoWriterInput.transform = videoTrack.preferredTransform
    
    let writer = try! AVAssetWriter(outputURL: outputURL, fileType: AVFileType.mp4)
    writer.add(videoWriterInput)
    
    let videoReaderSettings: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
    ]
    let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: videoReaderSettings)
    
    var videoReader: AVAssetReader!
    do {
        videoReader = try AVAssetReader(asset: videoAsset)
    }
    catch {
        print("videoReader cannot be created")
        completeHandler(.failure(error))
        return CompressionCancel()
    }
    videoReader.add(videoReaderOutput)
    
    
    let audioOutputSettingsDict: [String : Any] = [
        AVFormatIDKey : kAudioFormatMPEG4AAC,
        AVNumberOfChannelsKey : 2,
        AVSampleRateKey : compressionConfig.audioSampleRate.rawValue,
        AVEncoderBitRateKey : compressionConfig.audioBitrate
    ]
    let audioWriterInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: audioOutputSettingsDict)
    audioWriterInput.expectsMediaDataInRealTime = false
    writer.add(audioWriterInput)
    
    let audioReaderSettingsDict: [String : Any] = [
        AVFormatIDKey : kAudioFormatLinearPCM,
        AVSampleRateKey : 44100
    ]
    var audioReader: AVAssetReader?
    var audioReaderOutput: AVAssetReaderTrackOutput?
    if(audioTrack != nil) {
        audioReaderOutput = AVAssetReaderTrackOutput(track: audioTrack!, outputSettings: audioReaderSettingsDict)
        audioReader = try! AVAssetReader(asset: videoAsset)
        audioReader?.add(audioReaderOutput!)
    }
    
    writer.startWriting()
    videoReader.startReading()
    writer.startSession(atSourceTime: CMTime.zero)
    audioReader?.startReading()
    
    
    processingQueue.async {
        var videoDone = false
        var audioDone = false
        
        while !videoDone || !audioDone {
            if cancelable.cancel {
                audioReader?.cancelReading()
                videoReader.cancelReading()
                writer.cancelWriting()
                completeHandler(.cancelled)
                return
            }
            if videoWriterInput.isReadyForMoreMediaData {
                let sampleBuffer: CMSampleBuffer? = videoReaderOutput.copyNextSampleBuffer()
                if videoReader.status == .reading && sampleBuffer != nil {
                    if let handler = progressHandler {
                        progressQueue.async {
                            let presTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer!))
                            videoProgress.completedUnitCount = Int64(presTime)
                            handler(videoProgress)
                        }
                    }
                    videoWriterInput.append(sampleBuffer!)
                } else {
                    videoWriterInput.markAsFinished()
                    videoDone = true
                }
            }
            
            guard let audioReader = audioReader else {
                audioDone = true
                continue
            }
            
            if audioWriterInput.isReadyForMoreMediaData {
                let sampleBuffer: CMSampleBuffer? = audioReaderOutput?.copyNextSampleBuffer()
                if audioReader.status == .reading && sampleBuffer != nil {
                    /*if isFirstBuffer {
                        let dict = CMTimeCopyAsDictionary(CMTimeMake(value: 1024, timescale: 44100), allocator: kCFAllocatorDefault)
                        CMSetAttachment(sampleBuffer as CMAttachmentBearer, key: kCMSampleBufferAttachmentKey_TrimDurationAtStart, value: dict, attachmentMode: kCMAttachmentMode_ShouldNotPropagate)
                        isFirstBuffer = false
                    }*/
                    if let audioHandler = audioProgressHandler {
                        progressQueue.async {
                            let presTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer!))
                            audioProgress.completedUnitCount = Int64(presTime)
                            audioHandler(audioProgress)
                        }
                    }
                    audioWriterInput.append(sampleBuffer!)
                } else {
                    audioWriterInput.markAsFinished()
                    audioDone = true
                }
            }
        }
        
        writer.finishWriting(completionHandler: {() -> Void in
            completeHandler(.success(outputURL))
        })
    }
    
    
    return cancelable
}

/*
var size = UInt32(0)
var format = kAudioFormatMPEG4AAC

print(AudioFormatGetPropertyInfo(kAudioFormatProperty_AvailableEncodeSampleRates, UInt32(MemoryLayout<UInt32>.size), &format, &size))
var ranges = [AudioValueRange](repeating: AudioValueRange(), count: Int(size)/MemoryLayout<AudioValueRange>.size)
print(AudioFormatGetProperty(kAudioFormatProperty_AvailableEncodeSampleRates, UInt32(MemoryLayout<UInt32>.size), &format, &size, &ranges))
ranges.forEach { range in
    print("high:\(range.mMaximum), low: \(range.mMinimum)")
}
*/
