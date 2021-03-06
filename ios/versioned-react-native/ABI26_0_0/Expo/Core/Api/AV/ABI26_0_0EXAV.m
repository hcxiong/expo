// Copyright 2017-present 650 Industries. All rights reserved.

#import <AVFoundation/AVFoundation.h>

#import <ReactABI26_0_0/ABI26_0_0RCTUIManager.h>
#import <ReactABI26_0_0/ABI26_0_0RCTUIManagerUtils.h>
#import <ReactABI26_0_0/ABI26_0_0RCTUtils.h>

#import "ABI26_0_0EXAV.h"
#import "ABI26_0_0EXAVPlayerData.h"
#import "ABI26_0_0EXFileSystem.h"
#import "ABI26_0_0EXVideoView.h"
#import "ABI26_0_0EXUnversioned.h"

NSString *const ABI26_0_0EXAudioRecordingOptionsKey = @"ios";
NSString *const ABI26_0_0EXAudioRecordingOptionExtensionKey = @"extension";
NSString *const ABI26_0_0EXAudioRecordingOptionOutputFormatKey = @"outputFormat";
NSString *const ABI26_0_0EXAudioRecordingOptionAudioQualityKey = @"audioQuality";
NSString *const ABI26_0_0EXAudioRecordingOptionSampleRateKey = @"sampleRate";
NSString *const ABI26_0_0EXAudioRecordingOptionNumberOfChannelsKey = @"numberOfChannels";
NSString *const ABI26_0_0EXAudioRecordingOptionBitRateKey = @"bitRate";
NSString *const ABI26_0_0EXAudioRecordingOptionBitRateStrategyKey = @"bitRateStrategy";
NSString *const ABI26_0_0EXAudioRecordingOptionBitDepthHintKey = @"bitDepthHint";
NSString *const ABI26_0_0EXAudioRecordingOptionLinearPCMBitDepthKey = @"linearPCMBitDepth";
NSString *const ABI26_0_0EXAudioRecordingOptionLinearPCMIsBigEndianKey = @"linearPCMIsBigEndian";
NSString *const ABI26_0_0EXAudioRecordingOptionLinearPCMIsFloatKey = @"linearPCMIsFloat";

NSString *const ABI26_0_0EXDidUpdatePlaybackStatusEventName = @"didUpdatePlaybackStatus";

@interface ABI26_0_0EXAV ()

@property (nonatomic, assign) BOOL audioIsEnabled;
@property (nonatomic, assign) ABI26_0_0EXAVAudioSessionMode currentAudioSessionMode;
@property (nonatomic, assign) BOOL isBackgrounded;

@property (nonatomic, assign) ABI26_0_0EXAudioInterruptionMode audioInterruptionMode;
@property (nonatomic, assign) BOOL playsInSilentMode;
@property (nonatomic, assign) BOOL allowsAudioRecording;

@property (nonatomic, assign) int soundDictionaryKeyCount;
@property (nonatomic, strong) NSMutableDictionary <NSNumber *, ABI26_0_0EXAVPlayerData *> *soundDictionary;
@property (nonatomic, assign) BOOL isBeingObserved;
@property (nonatomic, strong) NSMutableSet <NSObject<ABI26_0_0EXAVObject> *> *videoSet;

@property (nonatomic, strong) NSString *audioRecorderFilename;
@property (nonatomic, strong) NSDictionary *audioRecorderSettings;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, assign) BOOL audioRecorderIsPreparing;
@property (nonatomic, assign) BOOL audioRecorderShouldBeginRecording;
@property (nonatomic, assign) int audioRecorderDurationMillis;

@end

@implementation ABI26_0_0EXAV

@synthesize methodQueue = _methodQueue;

- (instancetype)init
{
  if ((self = [super init])) {
    _audioIsEnabled = YES;
    _currentAudioSessionMode = ABI26_0_0EXAVAudioSessionModeInactive;
    _isBackgrounded = NO;
    
    _audioInterruptionMode = ABI26_0_0EXAudioInterruptionModeMixWithOthers;
    _playsInSilentMode = false;
    _allowsAudioRecording = false;
    
    _soundDictionaryKeyCount = 0;
    _soundDictionary = [NSMutableDictionary new];
    _isBeingObserved = NO;
    _videoSet = [NSMutableSet new];
    
    _audioRecorderFilename = nil;
    _audioRecorderSettings = nil;
    _audioRecorder = nil;
    _audioRecorderIsPreparing = false;
    _audioRecorderShouldBeginRecording = false;
    _audioRecorderDurationMillis = 0;
    
    // These only need to be set once:
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleAudioSessionInterruption:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:session];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleMediaServicesReset)
                                                 name:AVAudioSessionMediaServicesWereResetNotification
                                               object:session];
  }
  
  return self;
}

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

#pragma mark - Expo experience lifecycle

- (void)setBridge:(ABI26_0_0RCTBridge *)bridge
{
  [super setBridge:bridge];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_bridgeDidForeground:)
                                               name:@"EXKernelBridgeDidForegroundNotification"
                                             object:self.bridge];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_bridgeDidBackground:)
                                               name:@"EXKernelBridgeDidBackgroundNotification"
                                             object:self.bridge];
}

- (void)_bridgeDidForeground:(NSNotification *)notification
{
  _isBackgrounded = NO;
  
  [self _runBlockForAllAVObjects:^(NSObject<ABI26_0_0EXAVObject> *exAVObject) {
    [exAVObject bridgeDidForeground:notification];
  }];
}

- (void)_bridgeDidBackground:(NSNotification *)notification
{
  _isBackgrounded = YES;
  [self _deactivateAudioSession]; // This will pause all players and stop all recordings
  
  [self _runBlockForAllAVObjects:^(NSObject<ABI26_0_0EXAVObject> *exAVObject) {
    [exAVObject bridgeDidBackground:notification];
  }];
}

#pragma mark - ABI26_0_0RCTEventEmitter

- (void)startObserving
{
  _isBeingObserved = YES;
}

- (void)stopObserving
{
  _isBeingObserved = NO;
}

#pragma mark - Global audio state control API

- (void)registerVideoForAudioLifecycle:(NSObject<ABI26_0_0EXAVObject> *)video
{
  [_videoSet addObject:video];
}

- (void)unregisterVideoForAudioLifecycle:(NSObject<ABI26_0_0EXAVObject> *)video
{
  [_videoSet removeObject:video];
}

- (void)_runBlockForAllAVObjects:(void (^)(NSObject<ABI26_0_0EXAVObject> *exAVObject))block
{
  for (ABI26_0_0EXAVPlayerData *data in [_soundDictionary allValues]) {
    block(data);
  }
  for (NSObject<ABI26_0_0EXAVObject> *video in [_videoSet allObjects]) {
    block(video);
  }
}

// This method is placed here so that it is easily referrable from _setAudioSessionCategoryForAudioMode.
- (NSError *)_setAudioMode:(NSDictionary *)mode
{
  BOOL playsInSilentMode = ((NSNumber *)mode[@"playsInSilentModeIOS"]).boolValue;
  ABI26_0_0EXAudioInterruptionMode interruptionMode = ((NSNumber *)mode[@"interruptionModeIOS"]).intValue;
  BOOL allowsRecording = ((NSNumber *)mode[@"allowsRecordingIOS"]).boolValue;
  
  if (!playsInSilentMode && interruptionMode == ABI26_0_0EXAudioInterruptionModeDuckOthers) {
    return ABI26_0_0RCTErrorWithMessage(@"Impossible audio mode: playsInSilentMode and duckOthers cannot both be set on iOS.");
  } else if (!playsInSilentMode && allowsRecording) {
    return ABI26_0_0RCTErrorWithMessage(@"Impossible audio mode: playsInSilentMode and allowsRecording cannot both be set on iOS.");
  } else {
    if (!allowsRecording) {
      if (_audioRecorder && [_audioRecorder isRecording]) {
        [_audioRecorder pause];
      }
    }
    
    _playsInSilentMode = playsInSilentMode;
    _audioInterruptionMode = interruptionMode;
    _allowsAudioRecording = allowsRecording;
    
    if (_currentAudioSessionMode != ABI26_0_0EXAVAudioSessionModeInactive) {
      return [self _updateAudioSessionCategory:[AVAudioSession sharedInstance] forAudioSessionMode:[self _getAudioSessionModeRequired]];
    }
    return nil;
  }
}

- (NSError *)_updateAudioSessionCategory:(AVAudioSession *)audioSession forAudioSessionMode:(ABI26_0_0EXAVAudioSessionMode)audioSessionMode
{
  NSError *error;
  ABI26_0_0EXAudioInterruptionMode activeInterruptionMode = audioSessionMode == ABI26_0_0EXAVAudioSessionModeActiveMuted
    ? ABI26_0_0EXAudioInterruptionModeMixWithOthers : _audioInterruptionMode;
  
  if (!_playsInSilentMode) {
    // _allowsRecording is guaranteed to be false, and _interruptionMode is guaranteed to not be ABI26_0_0EXAudioInterruptionModeDuckOthers (see above)
    if (_audioInterruptionMode == ABI26_0_0EXAudioInterruptionModeDoNotMix) {
      [audioSession setCategory:AVAudioSessionCategorySoloAmbient error:&error];
    } else {
      [audioSession setCategory:AVAudioSessionCategoryAmbient error:&error];
    }
  } else {
    NSString *category = _allowsAudioRecording ? AVAudioSessionCategoryPlayAndRecord : AVAudioSessionCategoryPlayback;
    switch (activeInterruptionMode) {
      case ABI26_0_0EXAudioInterruptionModeDoNotMix:
        [audioSession setCategory:category error:&error];
        break;
      case ABI26_0_0EXAudioInterruptionModeDuckOthers:
        [audioSession setCategory:category withOptions:AVAudioSessionCategoryOptionDuckOthers error:&error];
        break;
      case ABI26_0_0EXAudioInterruptionModeMixWithOthers:
      default:
        [audioSession setCategory:category withOptions:AVAudioSessionCategoryOptionMixWithOthers error:&error];
        break;
    }
  }
  return error;
}

- (ABI26_0_0EXAVAudioSessionMode)_getAudioSessionModeRequired
{
  __block ABI26_0_0EXAVAudioSessionMode audioSessionModeRequired = ABI26_0_0EXAVAudioSessionModeInactive;
  
  [self _runBlockForAllAVObjects:^(NSObject<ABI26_0_0EXAVObject> *exAVObject) {
    ABI26_0_0EXAVAudioSessionMode audioSessionModeRequiredByThisObject = [exAVObject getAudioSessionModeRequired];
    if (audioSessionModeRequiredByThisObject > audioSessionModeRequired) {
      audioSessionModeRequired = audioSessionModeRequiredByThisObject;
    }
  }];
  
  if (_audioRecorder) {
    if (_audioRecorderShouldBeginRecording || [_audioRecorder isRecording]) {
      audioSessionModeRequired = ABI26_0_0EXAVAudioSessionModeActive;
    } else if (_audioRecorderIsPreparing && audioSessionModeRequired == ABI26_0_0EXAVAudioSessionModeInactive) {
      audioSessionModeRequired = ABI26_0_0EXAVAudioSessionModeActiveMuted;
    }
  }
  
  return audioSessionModeRequired;
}

- (NSError *)promoteAudioSessionIfNecessary
{
  if (!_audioIsEnabled) {
    return ABI26_0_0RCTErrorWithMessage(@"Expo Audio is disabled, so the audio session could not be activated.");
  }
  if (_isBackgrounded) {
    return ABI26_0_0RCTErrorWithMessage(@"This experience is currently in the background, so the audio session could not be activated.");
  }
  
  ABI26_0_0EXAVAudioSessionMode audioSessionModeRequired = [self _getAudioSessionModeRequired];
  
  if (_currentAudioSessionMode >= audioSessionModeRequired) {
    return nil;
  }
  
  AVAudioSession *session = [AVAudioSession sharedInstance];
  
  NSError *error = [self _updateAudioSessionCategory:session forAudioSessionMode:audioSessionModeRequired];
  if (error) {
    return error;
  }
  
  if (_currentAudioSessionMode == ABI26_0_0EXAVAudioSessionModeInactive) {
    [session setActive:YES error:&error];
    if (error) {
      return error;
    }
  }
  
  _currentAudioSessionMode = audioSessionModeRequired;
  return nil;
}

- (NSError *)_deactivateAudioSession
{
  if (_currentAudioSessionMode == ABI26_0_0EXAVAudioSessionModeInactive) {
    return nil;
  }
  
  // We must have all players, recorders, and videos paused in order to effectively deactivate the session.
  [self _runBlockForAllAVObjects:^(NSObject<ABI26_0_0EXAVObject> *exAVObject) {
    [exAVObject pauseImmediately];
  }];
  if (_audioRecorder && [_audioRecorder isRecording]) {
    [_audioRecorder pause];
  }
  
  NSError *error;
  AVAudioSession *session = [AVAudioSession sharedInstance];
  [session setActive:NO error:&error];
  // Restore the AVAudioSession to the system default for proper sandboxing.
  [session setCategory:AVAudioSessionCategorySoloAmbient error:&error];
  if (!error) {
    _currentAudioSessionMode = ABI26_0_0EXAVAudioSessionModeInactive;
  }
  return error;
}

- (NSError *)demoteAudioSessionIfPossible
{
  ABI26_0_0EXAVAudioSessionMode audioSessionModeRequired = [self _getAudioSessionModeRequired];
  
  if (_currentAudioSessionMode <= audioSessionModeRequired) {
    return nil;
  }
  
  if (audioSessionModeRequired == ABI26_0_0EXAVAudioSessionModeActiveMuted) {
    NSError *error = [self _updateAudioSessionCategory:[AVAudioSession sharedInstance] forAudioSessionMode:audioSessionModeRequired];
    if (!error) {
      _currentAudioSessionMode = ABI26_0_0EXAVAudioSessionModeActiveMuted;
    }
    return error;
  }
  return [self _deactivateAudioSession];
}

- (void)_handleAudioSessionInterruption:(NSNotification*)notification
{
  NSNumber *interruptionType = [[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey];
  if (interruptionType.unsignedIntegerValue == AVAudioSessionInterruptionTypeBegan) {
    _currentAudioSessionMode = ABI26_0_0EXAVAudioSessionModeInactive;
  }
  
  [self _runBlockForAllAVObjects:^(NSObject<ABI26_0_0EXAVObject> *exAVObject) {
    [exAVObject handleAudioSessionInterruption:notification];
  }];
}

- (void)_handleMediaServicesReset
{
  // See here: https://developer.apple.com/library/content/qa/qa1749/_index.html
  // (this is an unlikely notification to receive, but best practices suggests that we catch it just in case)
  
  _currentAudioSessionMode = ABI26_0_0EXAVAudioSessionModeInactive;
  
  [self _runBlockForAllAVObjects:^(NSObject<ABI26_0_0EXAVObject> *exAVObject) {
    [exAVObject handleMediaServicesReset:nil];
  }];
  
  if (_audioRecorder) {
    [self _removeAudioRecorder:NO];
    [self _createNewAudioRecorder];
    [_audioRecorder prepareToRecord];
  }
}

#pragma mark - Internal sound playback helper methods

- (void)_runBlock:(void (^)(ABI26_0_0EXAVPlayerData *data))block
  withSoundForKey:(nonnull NSNumber *)key
     withRejecter:(ABI26_0_0RCTPromiseRejectBlock)reject
{
  ABI26_0_0EXAVPlayerData *data = _soundDictionary[key];
  if (data) {
    block(data);
  } else {
    reject(@"E_AUDIO_NOPLAYER", nil, ABI26_0_0RCTErrorWithMessage(@"Player does not exist."));
  }
}

- (void)_removeSoundForKey:(NSNumber *)key
{
  ABI26_0_0EXAVPlayerData *data = _soundDictionary[key];
  if (data) {
    [data pauseImmediately];
    [self demoteAudioSessionIfPossible];
  }
  _soundDictionary[key] = nil;
}

#pragma mark - Internal video playback helper method

- (void)_runBlock:(void (^)(ABI26_0_0EXVideoView *view))block
withEXVideoViewForTag:(nonnull NSNumber *)ReactABI26_0_0Tag
     withRejecter:(ABI26_0_0RCTPromiseRejectBlock)reject
{
  // TODO check that the bridge is still valid after the dispatch
  dispatch_async(dispatch_get_main_queue(), ^{
    UIView *view = [self.bridge.uiManager viewForReactABI26_0_0Tag:ReactABI26_0_0Tag];
    if ([view isKindOfClass:[ABI26_0_0EXVideoView class]]) {
      dispatch_async(ABI26_0_0RCTGetUIManagerQueue(), ^{
        block((ABI26_0_0EXVideoView *)view);
      });
    } else {
      NSString *errorMessage = [NSString stringWithFormat:@"Invalid view returned from registry, expecting ABI26_0_0EXVideo, got: %@", view];
      reject(@"E_VIDEO_TAGINCORRECT", nil, ABI26_0_0RCTErrorWithMessage(errorMessage));
    }
  });
}

#pragma mark - Internal audio recording helper methods

- (NSString *)_getBitRateStrategyFromEnum:(NSNumber *)bitRateEnumSelected
{
  if (bitRateEnumSelected) {
    switch ([bitRateEnumSelected integerValue]) {
      case ABI26_0_0EXAudioRecordingOptionBitRateStrategyConstant:
        return AVAudioBitRateStrategy_Constant;
      case ABI26_0_0EXAudioRecordingOptionBitRateStrategyLongTermAverage:
        return AVAudioBitRateStrategy_LongTermAverage;
      case ABI26_0_0EXAudioRecordingOptionBitRateStrategyVariableConstrained:
        return AVAudioBitRateStrategy_VariableConstrained;
        break;
      case ABI26_0_0EXAudioRecordingOptionBitRateStrategyVariable:
        return AVAudioBitRateStrategy_Variable;
      default:
        return nil;
    }
  }
  return nil;
}

- (NSDictionary<NSString *, NSString *> *)_getAVKeysForRecordingOptionsKeys:(NSString *)bitRateStrategy
{
  return @{ABI26_0_0EXAudioRecordingOptionOutputFormatKey: AVFormatIDKey,
           ABI26_0_0EXAudioRecordingOptionAudioQualityKey:
             bitRateStrategy == AVAudioBitRateStrategy_Variable
           ? AVEncoderAudioQualityForVBRKey : AVEncoderAudioQualityKey,
           ABI26_0_0EXAudioRecordingOptionSampleRateKey: AVSampleRateKey,
           ABI26_0_0EXAudioRecordingOptionNumberOfChannelsKey: AVNumberOfChannelsKey,
           ABI26_0_0EXAudioRecordingOptionBitRateKey: AVEncoderBitRateKey,
           ABI26_0_0EXAudioRecordingOptionBitDepthHintKey: AVEncoderBitDepthHintKey,
           ABI26_0_0EXAudioRecordingOptionLinearPCMBitDepthKey: AVLinearPCMBitDepthKey,
           ABI26_0_0EXAudioRecordingOptionLinearPCMIsBigEndianKey: AVLinearPCMIsBigEndianKey,
           ABI26_0_0EXAudioRecordingOptionLinearPCMIsFloatKey: AVLinearPCMIsFloatKey};
}

- (UInt32)_getFormatIDFromString:(NSString *)typeString
{
  const char *s = typeString.UTF8String;
  UInt32 typeCode = s[3] | (s[2] << 8) | (s[1] << 16) | (s[0] << 24);
  return typeCode;
}

- (void)_setNewAudioRecorderFilenameAndSettings:(NSDictionary *)optionsFromJS
{
  NSDictionary *iosOptionsFromJS = optionsFromJS[ABI26_0_0EXAudioRecordingOptionsKey];
  
  NSString *extension = iosOptionsFromJS[ABI26_0_0EXAudioRecordingOptionExtensionKey];
  _audioRecorderFilename = [NSString stringWithFormat:@"recording-%@%@", [[NSUUID UUID] UUIDString], extension];
  
  NSString *bitRateStrategy = [self _getBitRateStrategyFromEnum:iosOptionsFromJS[ABI26_0_0EXAudioRecordingOptionBitRateStrategyKey]];
  NSDictionary<NSString *, NSString *> *avKeysForRecordingOptionsKeys = [self _getAVKeysForRecordingOptionsKeys:bitRateStrategy];
  
  NSMutableDictionary *recorderSettings = [NSMutableDictionary new];
  for (NSString *recordingOptionsKey in avKeysForRecordingOptionsKeys) {
    if (iosOptionsFromJS[recordingOptionsKey]) {
      recorderSettings[avKeysForRecordingOptionsKeys[recordingOptionsKey]] = iosOptionsFromJS[recordingOptionsKey];
    }
  }
  recorderSettings[AVEncoderBitRateStrategyKey] = bitRateStrategy;

  if (
      iosOptionsFromJS[ABI26_0_0EXAudioRecordingOptionOutputFormatKey] &&
      [iosOptionsFromJS[ABI26_0_0EXAudioRecordingOptionOutputFormatKey] isKindOfClass:[NSString class]]
      ) {
    recorderSettings[AVFormatIDKey] =
      @([self _getFormatIDFromString:iosOptionsFromJS[ABI26_0_0EXAudioRecordingOptionOutputFormatKey]]);
  }
  
  _audioRecorderSettings = recorderSettings;
}

- (NSError *)_createNewAudioRecorder
{
  if (_audioRecorder) {
    return ABI26_0_0RCTErrorWithMessage(@"Recorder already exists.");
  }
  
  NSString *directory = [self.bridge.scopedModules.fileSystem.cachesDirectory stringByAppendingPathComponent:@"AV"];
  [ABI26_0_0EXFileSystem ensureDirExistsWithPath:directory];
  NSString *soundFilePath = [directory stringByAppendingPathComponent:_audioRecorderFilename];
  NSURL *soundFileURL = [NSURL fileURLWithPath:soundFilePath];
  
  NSError *error;
  AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:soundFileURL
                                                          settings:_audioRecorderSettings
                                                             error:&error];
  if (error == nil) {
    _audioRecorder = recorder;
  }
  return error;
}

- (int)_getDurationMillisOfRecordingAudioRecorder
{
  return _audioRecorder ? (int) (_audioRecorder.currentTime * 1000) : 0;
}

- (NSDictionary *)_getAudioRecorderStatus
{
  if (_audioRecorder) {
    int durationMillisFromRecorder = [self _getDurationMillisOfRecordingAudioRecorder];
    // After stop, the recorder's duration goes to zero, so we replace it with the correct duration in this case.
    int durationMillis = durationMillisFromRecorder == 0 ? _audioRecorderDurationMillis : durationMillisFromRecorder;
    return @{@"canRecord": @(YES),
             @"isRecording": @([_audioRecorder isRecording]),
             @"durationMillis": @(durationMillis)};
  } else {
    return nil;
  }
}

- (BOOL)_checkAudioRecorderExistsOrReject:(ABI26_0_0RCTPromiseRejectBlock)reject
{
  if (_audioRecorder == nil) {
    reject(@"E_AUDIO_NORECORDER", nil, ABI26_0_0RCTErrorWithMessage(@"Recorder does not exist."));
  }
  return _audioRecorder != nil;
}

- (void)_removeAudioRecorder:(BOOL)removeFilenameAndSettings
{
  if (_audioRecorder) {
    [_audioRecorder stop];
    [self demoteAudioSessionIfPossible];
    _audioRecorder = nil;
  }
  if (removeFilenameAndSettings) {
    _audioRecorderFilename = nil;
    _audioRecorderSettings = nil;
  }
}

ABI26_0_0RCT_EXPORT_MODULE(ExponentAV);

- (NSArray<NSString *> *)supportedEvents
{
  return @[ABI26_0_0EXDidUpdatePlaybackStatusEventName];
}

#pragma mark - Audio API: Global settings

ABI26_0_0RCT_EXPORT_METHOD(setAudioIsEnabled:(BOOL)value
                           resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                           rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  _audioIsEnabled = value;
  
  if (!value) {
    [self _deactivateAudioSession];
  }
  resolve(nil);
}

ABI26_0_0RCT_EXPORT_METHOD(setAudioMode:(nonnull NSDictionary *)mode
                      resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                      rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  NSError *error = [self _setAudioMode:mode];
  
  if (error) {
    reject(@"E_AUDIO_AUDIOMODE", nil, error);
  } else {
    resolve(nil);
  }
}

#pragma mark - Unified playback API - Audio

ABI26_0_0RCT_EXPORT_METHOD(loadForSound:(nonnull NSDictionary *)source
                    withStatus:(nonnull NSDictionary *)status
                   withSuccess:(ABI26_0_0RCTResponseSenderBlock)loadSuccess
                     withError:(ABI26_0_0RCTResponseSenderBlock)loadError)
{
  NSNumber *key = @(_soundDictionaryKeyCount++);

  __weak __typeof__(self) weakSelf = self;
  ABI26_0_0EXAVPlayerData *data = [[ABI26_0_0EXAVPlayerData alloc] initWithEXAV:self
                                                   withSource:source
                                                   withStatus:status
                                         withLoadFinishBlock:^(BOOL success, NSDictionary *successStatus, NSString *error) {
                                           if (success) {
                                             loadSuccess(@[key, successStatus]);
                                           } else {
                                             [weakSelf _removeSoundForKey:key];
                                             loadError(@[error]);
                                           }
                                         }];
  data.errorCallback = ^(NSString *error) {
    __strong __typeof__(weakSelf) strongSelf = weakSelf;
    
    if (strongSelf) {
      [strongSelf _removeSoundForKey:key];
    }
  };
  
  data.statusUpdateCallback = ^(NSDictionary *status) {
    __strong __typeof__(weakSelf) strongSelf = weakSelf;
    if (strongSelf && strongSelf.isBeingObserved) {
      NSDictionary<NSString *, id> *response = @{@"key": key, @"status": status};
      [strongSelf sendEventWithName:ABI26_0_0EXDidUpdatePlaybackStatusEventName body:response];
    }
  };
  
  _soundDictionary[key] = data;
}

ABI26_0_0RCT_EXPORT_METHOD(unloadForSound:(nonnull NSNumber *)key
                        resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                        rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXAVPlayerData *data) {
    [self _removeSoundForKey:key];
    resolve([ABI26_0_0EXAVPlayerData getUnloadedStatus]);
  } withSoundForKey:key withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(setStatusForSound:(nonnull NSNumber *)key
                         withStatus:(nonnull NSDictionary *)status
                           resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                           rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXAVPlayerData *data) {
    [data setStatus:status
           resolver:resolve
           rejecter:reject];
  } withSoundForKey:key withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(getStatusForSound:(nonnull NSNumber *)key
                           resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                           rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXAVPlayerData *data) {
    NSDictionary *status = [data getStatus];
    resolve(status);
  } withSoundForKey:key withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(replaySound:(nonnull NSNumber *)key
                   withStatus:(nonnull NSDictionary *)status
                     resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                     rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXAVPlayerData *data) {
    [data replayWithStatus:status
                  resolver:resolve
                  rejecter:reject];
  } withSoundForKey:key withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(setErrorCallbackForSound:(nonnull NSNumber *)key
                              withCallback:(ABI26_0_0RCTResponseSenderBlock)callback)
{
  ABI26_0_0EXAVPlayerData *data = _soundDictionary[key];
  if (data) {
    __block BOOL used = NO; // ABI26_0_0RCTResponseSenderBlock can only be used once
    __weak __typeof__(self) weakSelf = self;
    data.errorCallback = ^(NSString *error) {
      __strong __typeof__(self) strongSelf = weakSelf;
      
      if (strongSelf && !used) {
        used = YES;
        [strongSelf _removeSoundForKey:key];
        callback(@[error]);
      }
    };
  }
}

#pragma mark - Unified playback API - Video

ABI26_0_0RCT_EXPORT_METHOD(loadForVideo:(nonnull NSNumber *)ReactABI26_0_0Tag
                        source:(nonnull NSDictionary *)source
                    withStatus:(nonnull NSDictionary *)status
                      resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                      rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXVideoView *view) {
    [view setSource:source withStatus:status resolver:resolve rejecter:reject];
  } withEXVideoViewForTag:ReactABI26_0_0Tag withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(unloadForVideo:(nonnull NSNumber *)ReactABI26_0_0Tag
                        resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                        rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXVideoView *view) {
    [view setSource:nil withStatus:nil resolver:resolve rejecter:reject];
  } withEXVideoViewForTag:ReactABI26_0_0Tag withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(setStatusForVideo:(nonnull NSNumber *)ReactABI26_0_0Tag
                         withStatus:(nonnull NSDictionary *)status
                           resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                           rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXVideoView *view) {
    [view setStatus:status resolver:resolve rejecter:reject];
  } withEXVideoViewForTag:ReactABI26_0_0Tag withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(replayVideo:(nonnull NSNumber *)ReactABI26_0_0Tag
                   withStatus:(nonnull NSDictionary *)status
                     resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                     rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXVideoView *view) {
    [view replayWithStatus:status resolver:resolve rejecter:reject];
  } withEXVideoViewForTag:ReactABI26_0_0Tag withRejecter:reject];
}

ABI26_0_0RCT_EXPORT_METHOD(getStatusForVideo:(nonnull NSNumber *)ReactABI26_0_0Tag
                           resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                           rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _runBlock:^(ABI26_0_0EXVideoView *view) {
    resolve(view.status);
  } withEXVideoViewForTag:ReactABI26_0_0Tag withRejecter:reject];
}

// Note that setStatusUpdateCallback happens in the JS for video via onStatusUpdate

#pragma mark - Audio API: Recording

ABI26_0_0RCT_EXPORT_METHOD(prepareAudioRecorder:(nonnull NSDictionary *)options
                              resolver:(ABI26_0_0RCTPromiseResolveBlock)resolve
                              rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  [self _setNewAudioRecorderFilenameAndSettings:options];
  NSError *error = [self _createNewAudioRecorder];
  
  if (_audioRecorder && !error) {
    _audioRecorderIsPreparing = true;
    error = [self promoteAudioSessionIfNecessary];
    if (error) {
      reject(@"E_AUDIO_RECORDERNOTCREATED", @"Prepare encountered an error: audio session not activated!", error);
    } else if ([_audioRecorder prepareToRecord]) {
      resolve(@{@"uri": [[_audioRecorder url] absoluteString],
                @"status": [self _getAudioRecorderStatus]});
    } else {
      reject(@"E_AUDIO_RECORDERNOTCREATED", nil, ABI26_0_0RCTErrorWithMessage(@"Prepare encountered an error: recorder not prepared."));
    }
    _audioRecorderIsPreparing = false;
    [self demoteAudioSessionIfPossible];
  } else {
    reject(@"E_AUDIO_RECORDERNOTCREATED", @"Prepare encountered an error: recorder not created.", error);
  }
}

ABI26_0_0RCT_EXPORT_METHOD(startAudioRecording:(ABI26_0_0RCTPromiseResolveBlock)resolve
                             rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  if ([self _checkAudioRecorderExistsOrReject:reject]) {
    if (!_allowsAudioRecording) {
      reject(@"E_AUDIO_AUDIOMODE", nil, ABI26_0_0RCTErrorWithMessage(@"Recording not allowed on iOS."));
    } else if (!_audioRecorder.recording) {
      _audioRecorderShouldBeginRecording = true;
      NSError *error = [self promoteAudioSessionIfNecessary];
      if (!error) {
        if ([_audioRecorder record]) {
          resolve([self _getAudioRecorderStatus]);
        } else {
          reject(@"E_AUDIO_RECORDING", nil, ABI26_0_0RCTErrorWithMessage(@"Start encountered an error: recording not started."));
        }
      } else {
        reject(@"E_AUDIO_RECORDING", @"Start encountered an error: audio session not activated.", error);
      }
    } else {
      resolve([self _getAudioRecorderStatus]);
    }
  }
  _audioRecorderShouldBeginRecording = false;
}

ABI26_0_0RCT_EXPORT_METHOD(pauseAudioRecording:(ABI26_0_0RCTPromiseResolveBlock)resolve
                             rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  if ([self _checkAudioRecorderExistsOrReject:reject]) {
    if (_audioRecorder.recording) {
      [_audioRecorder pause];
      [self demoteAudioSessionIfPossible];
    }
    resolve([self _getAudioRecorderStatus]);
  }
}

ABI26_0_0RCT_EXPORT_METHOD(stopAudioRecording:(ABI26_0_0RCTPromiseResolveBlock)resolve
                            rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  if ([self _checkAudioRecorderExistsOrReject:reject]) {
    if (_audioRecorder.recording) {
      _audioRecorderDurationMillis = [self _getDurationMillisOfRecordingAudioRecorder];
      [_audioRecorder stop];
      [self demoteAudioSessionIfPossible];
    }
    resolve([self _getAudioRecorderStatus]);
  }
}

ABI26_0_0RCT_EXPORT_METHOD(getAudioRecordingStatus:(ABI26_0_0RCTPromiseResolveBlock)resolve
                                 rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  if ([self _checkAudioRecorderExistsOrReject:reject]) {
    resolve([self _getAudioRecorderStatus]);
  }
}

ABI26_0_0RCT_EXPORT_METHOD(unloadAudioRecorder:(ABI26_0_0RCTPromiseResolveBlock)resolve
                             rejecter:(ABI26_0_0RCTPromiseRejectBlock)reject)
{
  if ([self _checkAudioRecorderExistsOrReject:reject]) {
    [self _removeAudioRecorder:YES];
    resolve(nil);
  }
}

#pragma mark - Lifecycle

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  
  // This will clear all @properties and deactivate the audio session:
  
  for (NSObject<ABI26_0_0EXAVObject> *video in [_videoSet allObjects]) {
    [video pauseImmediately];
    [_videoSet removeObject:video];
  }
  [self _removeAudioRecorder:YES];
  for (NSNumber *key in [_soundDictionary allKeys]) {
    [self _removeSoundForKey:key];
  }
}


@end
