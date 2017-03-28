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


protocol SelfPostingNotification {
    static var notificationName : Notification.Name { get }
}

extension SelfPostingNotification {
    static var userInfoKey : String { return notificationName.rawValue }
    
    func post() {
        NotificationCenter.default.post(name: type(of:self).notificationName,
                                        object: nil,
                                        userInfo: [type(of:self).userInfoKey : self])
    }
}



/// MARK - Video call observer

public typealias WireCallCenterObserverToken = NSObjectProtocol

struct WireCallCenterV3VideoNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterVideoNotification")
    
    let receivedVideoState : ReceivedVideoState
    
    init(receivedVideoState: ReceivedVideoState) {
        self.receivedVideoState = receivedVideoState
    }

}



/// MARK - Call state observer

public protocol WireCallCenterCallStateObserver : class {
    func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?)
}

public struct WireCallCenterCallStateNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterNotification")
    
    let callState : CallState
    let conversationId : UUID
    let userId : UUID?
}



/// MARK - Missed call observer

public protocol WireCallCenterMissedCallObserver : class {
    func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool)
}

public struct WireCallCenterMissedCallNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterMissedCallNotification")
    
    let conversationId : UUID
    let userId : UUID
    let timestamp: Date
    let video: Bool
}



/// MARK - ConferenceParticipantsObserver
protocol WireCallCenterConferenceParticipantsObserver : class {
    func callCenterConferenceParticipantsChanged(conversationId: UUID, userIds: [UUID])
}

struct WireCallCenterConferenceParticipantsChangedNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterNotification")
    
    let conversationId : UUID
    let userId : UUID
    let timestamp: Date
    let video: Bool
}



/// MARK - CBR observer

public protocol WireCallCenterCBRCallObserver : class {
    func callCenterCallIsCBR()
}

struct WireCallCenterCBRCallNotification {
    static let notificationName = Notification.Name("WireCallCenterCBRCallNotification")
    static let userInfoKey = notificationName.rawValue
    
    func post() {
        NotificationCenter.default.post(name: WireCallCenterCBRCallNotification.notificationName,
                                        object: nil,
                                        userInfo: [WireCallCenterCBRCallNotification.userInfoKey : self])
    }
}


extension WireCallCenterV3 {
    
    // MARK - Observer
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    /// Returns a token which needs to unregistered with `removeObserver(token:)` to stop observing.
    public class func addCallStateObserver(observer: WireCallCenterCallStateObserver) -> WireCallCenterObserverToken  {
        return NotificationCenter.default.addObserver(forName: WireCallCenterCallStateNotification.notificationName, object: nil, queue: .main) { [weak observer] (note) in
            if let note = note.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification {
                observer?.callCenterDidChange(callState: note.callState, conversationId: note.conversationId, userId: note.userId)
            }
        }
    }
    
    /// Register observer of missed calls.
    /// Returns a token which needs to unregistered with `removeObserver(token:)` to stop observing.
    public class func addMissedCallObserver(observer: WireCallCenterMissedCallObserver) -> WireCallCenterObserverToken  {
        return NotificationCenter.default.addObserver(forName: WireCallCenterMissedCallNotification.notificationName, object: nil, queue: .main) { [weak observer] (note) in
            if let note = note.userInfo?[WireCallCenterMissedCallNotification.userInfoKey] as? WireCallCenterMissedCallNotification {
                observer?.callCenterMissedCall(conversationId: note.conversationId, userId: note.userId, timestamp: note.timestamp, video: note.video)
            }
        }
    }
    
    /// Register observer of the video state. This will inform you when the remote caller starts, stops sending video.
    /// Returns a token which needs to unregistered with `removeObserver(token:)` to stop observing.
    public class func addReceivedVideoObserver(observer: ReceivedVideoObserver) -> WireCallCenterObserverToken {
        return NotificationCenter.default.addObserver(forName: WireCallCenterV3VideoNotification.notificationName, object: nil, queue: .main) { [weak observer] (note) in
            if let note = note.userInfo?[WireCallCenterV3VideoNotification.userInfoKey] as? WireCallCenterV3VideoNotification {
                observer?.callCenterDidChange(receivedVideoState: note.receivedVideoState)
            }
        }
    }
    
    public class func removeObserver(token: WireCallCenterObserverToken) {
        NotificationCenter.default.removeObserver(token)
    }
    
}


class VoiceChannelParticipantV3Snapshot {
    
    fileprivate var state : SetSnapshot
//    public private(set) var activeFlowParticipantsState : NSMutableOrderedSet
//    public private(set) var callParticipantState : NSMutableOrderedSet
    public private(set) var members : [CallMember]
    
    fileprivate let conversationId : UUID
    fileprivate let selfUserID : UUID
    let initiator : UUID
    
    init(conversationId: UUID, selfUserID: UUID, members: [CallMember]?, initiator: UUID? = nil) {
        self.conversationId = conversationId
        self.selfUserID = selfUserID
        self.initiator = initiator ?? selfUserID
        
        guard let callCenter = WireCallCenterV3.activeInstance else {
            fatal("WireCallCenterV3 not accessible")
        }
        
        let allMembers = members ?? callCenter.activeFlowParticipants(in: conversationId)
//        let (all, connected) = type(of:self).sort(participants: allMembers, selfUserID: selfUserID)
//        activeFlowParticipantsState = NSMutableOrderedSet(array: connected)
//        callParticipantState = NSMutableOrderedSet(array: all)
        self.members = allMembers
        state = SetSnapshot(set: NSOrderedSet(array: self.members), moveType: .uiCollectionView)
        print(state.set)
        notifyInitialChange()
    }
    
    func notifyInitialChange(){
        let changedIndexes = ZMChangedIndexes(start: ZMOrderedSetState(orderedSet: NSOrderedSet()),
                                              end: ZMOrderedSetState(orderedSet: NSOrderedSet(array: members)),
                                              updatedState: ZMOrderedSetState(orderedSet: NSOrderedSet()))!
        let changeInfo = SetChangeInfo(observedObject: conversationId as NSUUID,
                                       changeSet: changedIndexes,
                                       orderedSetState: NSOrderedSet())
        
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            VoiceChannelParticipantNotification(setChangeInfo: changeInfo, conversationId: self.conversationId).post()
        }
    }
    
    private static func sort(participants : [CallMember], selfUserID: UUID) -> (all: [UUID], connected: [UUID]) {
        var connected = [UUID]()
        let all : [UUID] = participants.flatMap{
            guard $0.remoteId != selfUserID else { return nil }
            if $0.audioEstablished {
                connected.append($0.remoteId)
            }
            return $0.remoteId
        }
        return (all, connected)
    }
    
    func callParticipantsChanged(newParticipants: [CallMember]) {
        // TODO Sabine : Rewrite ChangedIndexes in Swift?
        let added = newParticipants.filter{!members.contains($0)}
        let removed = members.filter{!newParticipants.contains($0)}

        removed.forEach{
            guard let idx = members.index(of: $0) else { return }
            members.remove(at: idx)
        }
        added.forEach{
            guard let idx = newParticipants.index(of: $0) else { return }
            members.insert($0, at: idx)
        }
        var updated : Set<CallMember> = Set()
        for m in members {
            guard let idx = newParticipants.index(of: m) else { continue }
            let newMember = newParticipants[idx]
            if newMember.audioEstablished != m.audioEstablished {
                updated.insert(m)
            }
        }
        recalculateSet(updated: updated)
    }
    
    /// calculate inserts / deletes / moves
    func recalculateSet(updated: Set<CallMember>) {
        guard let newStateUpdate = state.updatedState(NSOrderedSet(set: updated),
                                                      observedObject: conversationId as NSUUID,
                                                      newSet: NSOrderedSet(array: members))
        else { return}
        
        state = newStateUpdate.newSnapshot
        
        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else { return }
            VoiceChannelParticipantNotification(setChangeInfo: newStateUpdate.changeInfo, conversationId: self.conversationId).post()
        }
        
    }
    
    public func connectionState(forUserWith userId: UUID) -> VoiceChannelV2ConnectionState {
        let isJoined = members.map{$0.remoteId}.contains(userId)
        let isFlowActive = members.map{$0.remoteId}.contains(userId)
        
        switch (isJoined, isFlowActive) {
        case (false, _):    return .notConnected
        case (true, true):  return .connected
        case (true, false): return .connecting
        }
    }
}
