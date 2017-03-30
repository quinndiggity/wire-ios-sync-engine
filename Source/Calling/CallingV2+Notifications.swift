//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation

///////////
//// VoiceGainObserver
//////////

@objc
public protocol VoiceGainObserver : class {
    func voiceGainDidChange(forParticipant participant: ZMUser, volume: Float)
}

@objc
public class VoiceGainNotification : NSObject  {
    
    public static let notificationName = Notification.Name("VoiceGainNotification")
    public static let userInfoKey = notificationName.rawValue
    
    public let volume : Float
    public let userId : UUID
    public let conversationId : UUID
    
    public init(volume: Float, conversationId: UUID, userId: UUID) {
        self.volume = volume
        self.conversationId = conversationId
        self.userId = userId
        
        super.init()
    }
    
    public var notification : Notification {
        return Notification(name: VoiceGainNotification.notificationName,
                            object: conversationId as NSUUID,
                            userInfo: [VoiceGainNotification.userInfoKey : self])
    }
    
    public func post() {
        NotificationCenter.default.post(notification)
    }
}


///////////
//// CallEndedObserver
//////////

@objc
public class CallEndedNotification : NSObject {
    
    public static let notificationName = Notification.Name("CallEndedNotification")
    public static let userInfoKey = notificationName.rawValue
    
    public let reason : VoiceChannelV2CallEndReason
    public let conversationId : UUID
    
    public init(reason: VoiceChannelV2CallEndReason, conversationId: UUID) {
        self.reason = reason
        self.conversationId = conversationId
        
        super.init()
    }
    
    public func post() {
        NotificationCenter.default.post(name: CallEndedNotification.notificationName,
                                        object: nil,
                                        userInfo: [CallEndedNotification.userInfoKey : self])
    }
}




////////
//// VoiceChannelStateObserver
///////

@objc
public protocol WireCallCenterV2CallStateObserver : class {
    
    @objc(callCenterDidChangeVoiceChannelState:conversation:)
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation)
}


struct VoiceChannelStateNotification {
    
    static let notificationName = Notification.Name("VoiceChannelStateNotification")
    static let userInfoKey = notificationName.rawValue
    
    let voiceChannelState : VoiceChannelV2State
    let conversationId : NSManagedObjectID
    
    func post() {
        NotificationCenter.default.post(name: VoiceChannelStateNotification.notificationName,
                                        object: nil,
                                        userInfo: [VoiceChannelStateNotification.userInfoKey : self])
    }
}



///////////
//// VoiceChannelParticipantsObserver
///////////

@objc
public protocol VoiceChannelParticipantObserver : class {
    func voiceChannelParticipantsDidChange(_ changeInfo : VoiceChannelParticipantNotification)
}

public class VoiceChannelParticipantNotification : NSObject {

    static let notificationName = Notification.Name("VoiceChannelParticipantNotification")
    static let userInfoKey = notificationName.rawValue
    let setChangeInfoV2 : SetChangeInfoV2<CallMember>?
    let setChangeInfo: SetChangeInfo?
    let conversationId : UUID

    init(setChangeInfo: SetChangeInfo? = nil, setChangeInfoV2: SetChangeInfoV2<CallMember>? = nil, conversationId: UUID) {
        if setChangeInfoV2 == nil && setChangeInfo == nil {
            fatalError("One of the two should be set")
        }
        self.setChangeInfoV2 = setChangeInfoV2
        self.setChangeInfo = setChangeInfo
        self.conversationId = conversationId
    }
    
    public var insertedIndexes : IndexSet { return setChangeInfoV2?.insertedIndexes ?? setChangeInfo?.insertedIndexes ?? IndexSet()}
    public var deletedIndexes : IndexSet { return setChangeInfoV2?.deletedIndexes ?? setChangeInfo?.deletedIndexes ?? IndexSet()}
    public var updatedIndexes : IndexSet { return setChangeInfoV2?.updatedIndexes ?? setChangeInfo?.updatedIndexes ?? IndexSet()}
    public func enumerateMovedIndexes(_ block:@escaping (_ from: UInt, _ to : UInt) -> Void) {
        if let changeInfo = setChangeInfo {
            changeInfo.enumerateMovedIndexes(block)
        } else if let changeInfo = setChangeInfoV2 {
            changeInfo.enumerateMovedIndexes(block)
        }
    }
    
    open var movedIndexPairs : [ZMMovedIndex] {
        return setChangeInfo?.movedIndexPairs ?? setChangeInfoV2?.movedIndexPairs ?? []
    }
    
    func post() {
        NotificationCenter.default.post(name: VoiceChannelParticipantNotification.notificationName,
                                        object: nil,
                                        userInfo: [VoiceChannelParticipantNotification.userInfoKey : self])
    }
}



///////
//// VideoObserver
//////

struct VoiceChannelVideoChangedNotification {
    
    static let notificationName = Notification.Name("VoiceChannelVideoChangedNotification")
    static let userInfoKey = notificationName.rawValue
    let receivedVideoState : ReceivedVideoState
    let conversation : ZMConversation
    
    func post() {
        NotificationCenter.default.post(name: VoiceChannelVideoChangedNotification.notificationName,
                                        object: conversation,
                                        userInfo: [VoiceChannelVideoChangedNotification.userInfoKey : self])
    }
}


