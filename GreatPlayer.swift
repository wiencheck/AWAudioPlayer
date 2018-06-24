//
//  GreatPlayer.swift
//
//  Created by Adam Wienconek on 22.06.2018.
//  Copyright © 2018 Adam Wienconek. All rights reserved.
//

import Foundation
import MediaPlayer

class GreatPlayer: NSObject {
    
    /* Shared singleton of the class, you use it in your app and spierdalaj */
    static public let shared = GreatPlayer()
    
    // MARK: Public variables
    
    /* Should now playing info show on lock screen and control center? */
    public var shouldUpdateNowPlayingInfoCenter = true
    
    /* Should controls (previous, play/pause, next) show on lockscreen and in control center? */
    public var shouldShowRemoteControls = true
    
    /* Currently playing item */
    public var nowPlayingItem: MPMediaItem?
    
    /* AVAsset created from nowPlayingItem */
    public var nowPlayingAsset: AVAsset? {
        guard let url = nowPlayingItem?.assetURL else { return nil }
        return AVAsset(url: url)
    }
    
    /*  */
    public var playbackMode = PlaybackMode.default {
        didSet {
            NotificationCenter.default.post(name: .playbackModeChanged, object: nil)
        }
    }
    
    /* */
    public var repeatMode = RepeatMode.none {
        didSet {
            NotificationCenter.default.post(name: .repeatModeChanged, object: nil)
        }
    }
    /* */
    public var state = PlaybackState.initial {
        didSet {
            NotificationCenter.default.post(name: .playbackStateChanged, object: nil)
        }
    }
    
    public var indexOfNowPlayingItem = 0
    
    /*
        Currently used object of AVAudioPlayer class
        typically you should not use it as most use cases are handled by GreatPlayer,
        however it is exposed in case you would like to access some strange properties of AVAudioPlayer
     */
    public var player: AVAudioPlayer! {
        return playerFlag == 1 ? player1 : player2
    }
    
    /*
        "Is it playing or not?"
        source, Apple's documentation
     */
    public var isPlaying: Bool {
        return player.isPlaying
    }
    
    /* Current playback time in seconds */
    public var currentPlaybackTime: Double {
        get {
            return player.currentTime
        } set {
            player.currentTime = newValue
        }
    }
    
    /* Self explanatory */
    public var remainingPlaybackTime: TimeInterval {
        return self.player.duration - self.player.currentTime
    }
    
    /* Current player's rate, 0.5 is half speed, 0.2 is 20% etc. if returns 0.0 then player is paused */
    public var currentPlaybackRate: Float {
        get {
            return player.rate
        } set {
            player.rate = newValue
        }
    }
    
    public enum PlaybackMode {
        case `default`
        case shuffle
    }
    
    public enum RepeatMode {
        case none
        case one
        case all
    }
    
    public enum PlaybackState {
        case initial
        case playing
        case paused
        case interrupted
    }
    
    private let session = AVAudioSession.sharedInstance()
    
    private var player1: AVAudioPlayer!
    private var player2: AVAudioPlayer!
    
    private var playerFlag = 1
    
    private var originalQueue = [MPMediaItem]()
    public private(set)var queue = [MPMediaItem]() {
        didSet { NotificationCenter.default.post(name: .queueChanged, object: nil) }
    }
    private var customQueue = [MPMediaItem]()
    private var customIndex = 0
    
    private override init() {
        
        let url = URL(fileURLWithPath: Bundle.main.path(forResource: "initPlum", ofType: "m4a")!)
        do {
            player1 = try AVAudioPlayer(contentsOf: url)
            try session.setCategory(AVAudioSessionCategoryPlayback)
        } catch let err {
            print("*** Error when setting AVAudioSessionCategory ***\n\(err.localizedDescription)")
        }
        super.init()
        addAudioSessionObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.endReceivingRemoteControlEvents()
        activatePlaybackCommands(false)
        setSession(active: false)
    }
    
    private var timeTimer: Timer!
    
    private var shouldTrackCurrentTime = true
    
    private func trackCurrentTime() {
        timeTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { (_) in
            print("\(self.remainingPlaybackTime), \(self.player.currentTime)")
            if self.remainingPlaybackTime < 2 && self.shouldTrackCurrentTime {
                self.shouldReduceGap = true
                self.skipToNextTrack()
                self.shouldTrackCurrentTime = false
            }
        })
    }
    
    private var shouldReduceGap = false
    
    func setNowPlayingItem(_ item: MPMediaItem) {
        guard let url = item.assetURL else {
            print("*** Chosen item does not have proper URL ***")
            return
        }
        if shouldReduceGap {
            let time = player.deviceCurrentTime + 0.01 + remainingPlaybackTime
            if playerFlag == 2 {
                player1 = try! AVAudioPlayer(contentsOf: url)
                player1.prepareToPlay()
                player1.delegate = self
                playerFlag = 1
                player1.play(atTime: time)
                Timer.scheduledTimer(withTimeInterval: 2.1, repeats: false) { (_) in
                    print("WOWOWOWOWOWOWOWOWOWOWOWOWOWOW1")
                    self.shouldTrackCurrentTime = true
                }
                print("player1 playAt")
            } else {
                player2 = try! AVAudioPlayer(contentsOf: url)
                player2.prepareToPlay()
                player2.delegate = self
                playerFlag = 2
                player2.play(atTime: time)
                Timer.scheduledTimer(withTimeInterval: 2.1, repeats: false) { (_) in
                    print("WOWOWOWOWOWOWOWOWOWOWOWOWOWOW2")
                    self.shouldTrackCurrentTime = true
                }
                print("player2 playAt")
            }
        } else {
            playerFlag = 1
            player2 = nil
            player1 = try! AVAudioPlayer(contentsOf: url)
        }
        nowPlayingItem = item
    }
    
    public func setOriginalQueue(with items: [MPMediaItem]) {
        originalQueue = items
        queue = originalQueue
        indexOfNowPlayingItem = 0
    }
    
    public func setQueue() {
        switch playbackMode {
        case .shuffle:
            queue = originalQueue.shuffled()
        default:
            queue = originalQueue
        }
        indexOfNowPlayingItem = 0
    }
    
    private var shouldPlayFromCustomQueue: Bool {
        return customIndex >= customQueue.count - 1 && !customQueue.isEmpty
    }
    
    public func skipToNextTrack() {
        if shouldPlayFromCustomQueue {
            playCustomItemAtIndex(customIndex + 1)
        } else {
            setItemAtIndex(indexOfNowPlayingItem + 1)
        }
        shouldReduceGap = false
    }
    
    public func skipToBeginning() {
        player.currentTime = 0
    }
    
    public func skipToPrevious() {
        if currentPlaybackTime > 3.0 {
            skipToBeginning()
        }
    }
    
    func playCustomItemAtIndex(_ index: Int) {
        customIndex = index
        setNowPlayingItem(customQueue[customIndex])
        play()
    }
    
    func setItemAtIndex(_ index: Int) {
        print("\(queue.count) items")
        indexOfNowPlayingItem = index
        setNowPlayingItem(queue[indexOfNowPlayingItem])
    }
    
    func playItem(_ item: MPMediaItem) {
        guard let index = queue.index(of: item) else { return }
        setItemAtIndex(index)
    }
    
    // MARK: Playback
    
    public func play() {
        player.play()
        if state == .initial {
            UIApplication.shared.beginReceivingRemoteControlEvents()
            if shouldShowRemoteControls { activatePlaybackCommands(true) }
            if shouldUpdateNowPlayingInfoCenter { startNowPlayingInfoUpdates() }
            trackCurrentTime()
            setSession(active: true)
        } else if state == .interrupted || state == .paused {
            //setSession(active: true)
        }
        state = .playing
    }
    
    public func pause() {
        player.pause()
        //setSession(active: false)
        state = .paused
    }
    
    public func stop() {
        setSession(active: false)
        state = .paused
        player.pause()
        skipToBeginning()
    }
    
    public func togglePlayback() {
        switch state {
        case .playing:
            pause()
        default:
            play()
        }
    }
    
    public func setPlaybackState(_ state: PlaybackState) {
        self.state = state
    }
    
    public func setPlaybackMode(_ mode: PlaybackMode) {
        self.playbackMode = mode
        setQueue()
    }
    
    public func setRepeatMode(_ mode: RepeatMode) {
        self.repeatMode = mode
    }
    
    // MARK: Queue management (motherfucker)
    
    func addNext(_ item: MPMediaItem) {
        customQueue.insert(item, at: customIndex + 1)
    }
    
    func addLast(_ item: MPMediaItem) {
        customQueue.append(item)
    }
    
    // MARK: Notifications
    
    private func addAudioSessionObservers() {
        NotificationCenter.default.addObserver(forName: Notification.Name.AVAudioSessionInterruption, object: nil, queue: nil, using: { notification in
            self.handleAudioSessionInterruption(notification)
        })
        NotificationCenter.default.addObserver(forName: Notification.Name.AVAudioSessionRouteChange, object: nil, queue: nil, using: { notification in
            self.handleAudioRouteChanged(notification)
        })
    }
    
    private var shouldResumeAfterInterruption = true
    
    private func handleAudioRouteChanged(_ notification: Notification) {
        let audioRouteChangeReason = notification.userInfo![AVAudioSessionRouteChangeReasonKey] as! UInt
        switch audioRouteChangeReason {
        case AVAudioSessionRouteChangeReason.newDeviceAvailable.rawValue:
            print("headphone plugged in")
        case AVAudioSessionRouteChangeReason.oldDeviceUnavailable.rawValue:
            print("Route changed")
            pause()
        case AVAudioSessionRouteChangeReason.routeConfigurationChange.rawValue:
            print("Route configuration Change")
        case AVAudioSessionRouteChangeReason.categoryChange.rawValue:
            print("Category change")
        case AVAudioSessionRouteChangeReason.noSuitableRouteForCategory.rawValue:
            print("No suitable Route For Category")
        default:
            print("Default reason")
        }
    }
    
    private func handleAudioSessionInterruption(_ notification: Notification){
        print("Interruption received: \(notification.description)")
        guard let userInfo = notification.userInfo, let typeInt = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt, let interruptionType = AVAudioSessionInterruptionType(rawValue: typeInt), let optionsInt = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
        
        let interruptionOptions = AVAudioSessionInterruptionOptions(rawValue: optionsInt)
        shouldResumeAfterInterruption = interruptionOptions.contains(.shouldResume)
        switch interruptionType {
        case .began:
            pause()
            state = .interrupted
        case .ended:
            if shouldResumeAfterInterruption { play() }
        }
    }
    
    // MARK: Now playing info
    
    private var cc = MPNowPlayingInfoCenter.default()
    private var infoTimer: Timer!
    
    private func updateNowPlayingInfo() {
        guard let _ = nowPlayingItem?.assetURL else { return }
        var nowPlayingInfo = cc.nowPlayingInfo ?? [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = nowPlayingItem?.title ?? "Unknown title"
        nowPlayingInfo[MPMediaItemPropertyArtist] = nowPlayingItem?.albumArtist ?? "Unknown artist"
        nowPlayingInfo[MPMediaItemPropertyArtwork] = nowPlayingItem?.artwork
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentPlaybackTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = nowPlayingItem?.playbackDuration
        cc.nowPlayingInfo = nowPlayingInfo
    }
    
    private func startNowPlayingInfoUpdates() {
        if infoTimer == nil { infoTimer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true, block: { (_) in
            if self.isPlaying { self.updateNowPlayingInfo() }
        }) }
        if !infoTimer.isValid { infoTimer.fire() }
    }
    
    private func endNowPlayingInfoUpdates() {
        if infoTimer.isValid { infoTimer.invalidate() }
    }
    
    // MARK: Other public methods
    
    public var nowPlayingItemRating: Int {
        get {
            return nowPlayingItem?.rating ?? 0
        } set {
            nowPlayingItem?.setValue(newValue, forKey: MPMediaItemPropertyRating)
        }
    }
    
    private func setSession(active: Bool) {
        do {
            try session.setActive(active)
        } catch let err {
            print(err.localizedDescription)
        }
    }

    // MARK: Remote control events
    
    private func activatePlaybackCommands(_ enable: Bool){
        let remote = MPRemoteCommandCenter.shared()
        if enable {
            remote.togglePlayPauseCommand.addTarget(handler: { _ in
                self.togglePlayback()
                return .success
            })
            remote.playCommand.addTarget(handler: { _ in
                self.play()
                return .success
            })
            remote.pauseCommand.addTarget(handler: { _ in
                self.pause()
                return .success
            })
            remote.stopCommand.addTarget(handler: { _ in
                self.stop()
                return .success
            })
            remote.changePlaybackPositionCommand.addTarget { event -> MPRemoteCommandHandlerStatus in
                guard let time = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                self.currentPlaybackTime = time.positionTime
                return .success
            }
            remote.nextTrackCommand.addTarget(handler: { _ in
                self.skipToNextTrack()
                if self.state == .playing { self.play() }
                return .success
            })
            remote.previousTrackCommand.addTarget(handler: { _ in
                self.skipToPrevious()
                if self.state == .playing { self.play() }
                return .success
            })
            remote.changeShuffleModeCommand.addTarget(handler: { _ in
                //self.handleShuffleCommandEvent(event)
                return .success
            })
        }
        else {
            remote.playCommand.removeTarget(self)
            remote.pauseCommand.removeTarget(self)
            remote.stopCommand.removeTarget(self)
            remote.togglePlayPauseCommand.removeTarget(self)
            remote.changePlaybackPositionCommand.removeTarget(self)
            remote.nextTrackCommand.removeTarget(self)
            remote.previousTrackCommand.removeTarget(self)
            remote.changeShuffleModeCommand.removeTarget(self)
        }
        
        remote.playCommand.isEnabled = enable
        remote.pauseCommand.isEnabled = enable
        remote.stopCommand.isEnabled = enable
        remote.togglePlayPauseCommand.isEnabled = enable
        remote.changePlaybackPositionCommand.isEnabled = enable
        remote.nextTrackCommand.isEnabled = enable
        remote.previousTrackCommand.isEnabled = enable
        remote.changeShuffleModeCommand.isEnabled = enable
    }
    
}

extension GreatPlayer: AVAudioPlayerDelegate {
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
//        if shouldReduceGap {
//            self.player = playerFlag == 1 ? player1 : player2
//        }
        shouldReduceGap = false
        print("Shouldgap = \(shouldReduceGap)")
//        if shouldReduceGap {
//            self.player = playerFlag == 1 ? player1 : player2
//            shouldReduceGap = false
//        }
//        if player == self.player {
//            print("player finished")
//        }
        if player == self.player1 {
            print("player1 finished")
        } else if player == self.player2 {
            print("player2 finished")
        }
//         else {
//            if shouldSkip {
//                skipToNextTrack()
//            }
//        }
//        shouldSkip = true
    }
    
}

extension Notification.Name {
    
    static let trackChanged = Notification.Name("trackChanged")
    static let playbackStateChanged = Notification.Name("playbackStateChanged")
    static let queueChanged = Notification.Name("queueChanged")
    static let nextTrack = Notification.Name("nextTrack")
    static let previousTrack = Notification.Name("previousTrack")
    static let playbackModeChanged = Notification.Name("playbackModeChanged")
    static let repeatModeChanged = Notification.Name("repeatModeChanged")
}

extension MPMediaItem {
    
    var lyrics: String? {
        guard let url = self.assetURL else { return nil }
        let ass = AVAsset(url: url)
        return ass.lyrics
    }
    
}
