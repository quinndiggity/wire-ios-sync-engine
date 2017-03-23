//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

struct V2CallStateChange {
    let conversation : ZMConversation
    let state : VoiceChannelV2State
}

class VoiceChannelStateTestObserver : VoiceChannelStateObserver {

    var changes : [V2CallStateChange] = []
    var token : WireCallCenterObserverToken?
    
    func observe(conversation: ZMConversation, context: NSManagedObjectContext) {
        token = WireCallCenter.addVoiceChannelStateObserver(observer: self, context: context)
    }

    func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        //
    }
    
    func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        //
    }
    
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        changes.append(V2CallStateChange(conversation: conversation, state: voiceChannelState))
    }
    
    func checkLastNotificationHasCallState(_ callState: VoiceChannelV2State, line: UInt = #line, file : StaticString = #file) {
        guard let change = changes.last else {
            return XCTFail("Did not receive a notification", file: file, line: line)
        }
        XCTAssertEqual(change.state.rawValue, callState.rawValue, file: file, line: line)
    }
}

class VoiceChannelParticipantTestObserver : VoiceChannelParticipantObserver {
    
    var changes : [SetChangeInfo] = []
    var token : WireCallCenterObserverToken?
    
    func observe(conversation: ZMConversation, context: NSManagedObjectContext) {
        token = WireCallCenter.addVoiceChannelParticipantObserver(observer: self, forConversation: conversation, context: context)
    }
    
    func voiceChannelParticipantsDidChange(_ changeInfo: SetChangeInfo) {
        changes.append(changeInfo)
    }
}

class CallingV3Tests : IntegrationTestBase {
    
    var stateObserver : VoiceChannelStateTestObserver!
    var participantObserver : VoiceChannelParticipantTestObserver!
    
    override func setUp() {
        super.setUp()
        stateObserver = VoiceChannelStateTestObserver()
        participantObserver = VoiceChannelParticipantTestObserver()
    }
    
    override func tearDown() {
        stateObserver = nil
        super.tearDown()
    }
    
    func selfJoinCall() {
        userSession.enqueueChanges {
            _ = self.conversationUnderTest.voiceChannelRouter?.v3.join(video: false)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func selfDropCall(){
        userSession.enqueueChanges {
            self.conversationUnderTest.voiceChannelRouter?.v3.leave()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func otherJoinCall(){
        if useGroupConversation {
            let user = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
            simulateParticipantsChanged(user: user, establishedFlow: false)
        } else {
            simulateEstablishedFlow(user: conversationUnderTest.connectedUser!)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    private var wireCallCenterRef : UnsafeMutableRawPointer? {
        return Unmanaged<WireCallCenterV3>.passUnretained(WireCallCenterV3.activeInstance!).toOpaque()
    }
    
    private var conversationIdRef : [CChar]? {
        return conversationUnderTest.remoteIdentifier!.transportString().cString(using: .utf8)
    }
    
    func simulateEstablishedFlow(user: ZMUser){
        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        EstablishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: wireCallCenterRef)
    }
    
    func simulateParticipantsChanged(user: ZMUser, establishedFlow: Bool) {
        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        let userPointer = UnsafeMutablePointer<Int8>(mutating: userIdRef)
        
        var member = wcall_member(userid: userPointer, audio_estab: establishedFlow ? 1 : 0)
        var members = wcall_members(membv: &member, membc: 1)
        
        GroupMemberHandler(conversationIdRef: conversationIdRef, callMembersRef: &members, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        userPointer?.deinitialize()
    }

    func simulateCallClosed(user: ZMUser, reason: CallClosedReason) {
        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        ClosedCallHandler(reason: reason.rawValue, conversationId: conversationIdRef, userId: userIdRef, metrics: nil, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    var useGroupConversation : Bool = false
    var mockConversationUnderTest : MockConversation {
        return useGroupConversation ? groupConversation : selfToUser2Conversation
    }
    
    var conversationUnderTest : ZMConversation {
        return conversation(for: mockConversationUnderTest)
    }
    
    var localSelfUser : ZMUser {
        return user(for: selfUser)
    }
    
    func testJoiningAndLeavingAnEmptyVoiceChannel_OneOnOne(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete());
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)

        // when
        selfJoinCall()
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        
        // when
        selfDropCall()
        simulateCallClosed(user: self.localSelfUser, reason: .canceled)

        // then
        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }
    
    func testJoiningAndLeavingAnEmptyVoiceChannel_Group(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete());
        useGroupConversation = true
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        
        // when
        selfJoinCall()
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        
        // when
        selfDropCall()
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.incomingCallInactive)

        // and when
        simulateCallClosed(user: self.localSelfUser, reason: .canceled)

        XCTAssertEqual(stateObserver.changes.count, 3)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }
    
    func testThatItSendsOutAllExpectedNotificationsWhenSelfUserCalls_OneOnOne() {
        
        // no active users -> self is calling -> self connected to active channel -> no active users
    
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        participantObserver.observe(conversation: conversationUnderTest, context: uiMOC)

        // (1) self calling & backend acknowledges
        //
        // when
        selfJoinCall()
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        XCTAssertEqual(participantObserver.changes.count, 0)
        
        // (2) other party joins
        //
        // when
        otherJoinCall()
        
        // then
        stateObserver.checkLastNotificationHasCallState(.selfConnectedToActiveChannel)

        // TODO Sabine: Do we get these updates for 1on1 as well?
//        XCTAssertEqual(participantObserver.changes.count, 1)
//        if let partInfo =  participantObserver.changes.last {
//            XCTAssertEqual(partInfo.insertedIndexes, IndexSet(integer: 0))
//            XCTAssertEqual(partInfo.updatedIndexes, IndexSet())
//            XCTAssertEqual(partInfo.deletedIndexes, IndexSet())
//            XCTAssertEqual(partInfo.movedIndexPairs, [])
//        }
        
//        // (3) flow aquired
//        //
//        // when
//        [self simulateMediaFlowEstablishedOnConversation:oneToOneConversation];
//        [self simulateParticipantsChanged:@[self.user2] onConversation:oneToOneConversation];
//        WaitForAllGroupsToBeEmpty(0.5);
//        
//        // then
//        XCTAssertEqual(stateObserver.changes.count, 3u);
//        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
//        
//        XCTAssertEqual(participantObserver.changes.count, 2u);
//        SetChangeInfo *partInfo3 = participantObserver.changes.lastObject;
//        XCTAssertEqual(partInfo3.insertedIndexes, [NSIndexSet indexSet]);
//        XCTAssertEqual(partInfo3.updatedIndexes, [NSIndexSet indexSetWithIndex:0]);
//        XCTAssertEqual(partInfo3.deletedIndexes, [NSIndexSet indexSet]);
//        XCTAssertEqual(partInfo3.movedIndexPairs, @[]);
//        
        // (4) self user leaves
        //
        // when
        selfDropCall()
        simulateCallClosed(user: self.localSelfUser, reason: .canceled)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 3)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
        
//        XCTAssertEqual(participantObserver.changes.count, 3)
//        if let partInfo = participantObserver.changes.last {
//            XCTAssertEqual(partInfo.insertedIndexes, IndexSet())
//            XCTAssertEqual(partInfo.updatedIndexes, IndexSet())
////            XCTAssertEqual(partInfo.deletedIndexes, IndexSet(integersIn: Range(0, 0)))
//            XCTAssertEqual(partInfo.movedIndexPairs, [])
//        }
    }
    
    func testThatItSendsOutAllExpectedNotificationsWhenSelfUserCalls_Group() {
        
        // no active users -> self is calling -> self connected to active channel -> no active users
        
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        useGroupConversation = true
        
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        participantObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        
        // (1) self calling & backend acknowledges
        //
        // when
        selfJoinCall()
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        XCTAssertEqual(participantObserver.changes.count, 0)
        
        // (2) other party joins
        //
        // when
        let otherUser = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
        simulateParticipantsChanged(user: otherUser, establishedFlow: false)
        
        // then
        XCTAssertEqual(participantObserver.changes.count, 1)
        if let partInfo =  participantObserver.changes.last {
            XCTAssertEqual(partInfo.insertedIndexes, IndexSet(integer: 0))
            XCTAssertEqual(partInfo.updatedIndexes, IndexSet())
            XCTAssertEqual(partInfo.deletedIndexes, IndexSet())
            XCTAssertEqual(partInfo.movedIndexPairs, [])
        }
        
        // (3) flow aquired
        //
        // when
        simulateParticipantsChanged(user: otherUser, establishedFlow: true)
        
        // then
        XCTAssertEqual(participantObserver.changes.count, 2)
        if let partInfo =  participantObserver.changes.last {
            XCTAssertEqual(partInfo.insertedIndexes, IndexSet())
            XCTAssertEqual(partInfo.updatedIndexes, IndexSet(integer: 0))
            XCTAssertEqual(partInfo.deletedIndexes, IndexSet())
            XCTAssertEqual(partInfo.movedIndexPairs, [])
        }
        
        // (4) self user leaves
        //
        // when
        selfDropCall()
        simulateCallClosed(user: self.localSelfUser, reason: .canceled)
        
        // then
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }
}



/*

 

 
 - (void)testThatItSendsOutAllExpectedNotificationsWhenOtherUserCalls
 {
 ///3333333
 // given
 XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
 ZMConversation * NS_VALID_UNTIL_END_OF_SCOPE oneToOneConversation = self.conversationUnderTest;
 
 V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
 V2VoiceChannelParticipantTestObserver *participantObserver = [[V2VoiceChannelParticipantTestObserver alloc] init];
 
 id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
 id participantToken = [WireCallCenterV2 addVoiceChannelParticipantObserverWithObserver:participantObserver forConversation:oneToOneConversation context:self.uiMOC];
 
 // (1) other user joins
 // when
 [self otherJoinCall];
 WaitForAllGroupsToBeEmpty(0.5);
 
 // then
 XCTAssertEqual(stateObserver.changes.count, 1u);
 XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCall);
 
 // (2) we join
 // when
 [self selfJoinCall];
 WaitForAllGroupsToBeEmpty(0.5);
 
 // then
 {
 XCTAssertEqual(stateObserver.changes.count, 2u);
 XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
 [participantObserver.changes removeAllObjects];
 }
 
 // (3) flow aquired
 //
 // when
 [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
 [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
 WaitForAllGroupsToBeEmpty(0.5);
 
 // then
 {
 XCTAssertEqual(stateObserver.changes.count, 3u);
 XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
 XCTAssertEqual(participantObserver.changes.count, 1u); // we notify that user connected
 }
 
 // (4) the other user leaves. The backend tells us we are both idle
 
 [self otherDropsCall];
 WaitForAllGroupsToBeEmpty(0.5);
 
 // then
 {
 XCTAssertEqual(stateObserver.changes.count, 5u); // goes through transfer state before disconnect
 XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
 }
 
 [WireCallCenterV2 removeObserverWithToken:stateToken];
 [WireCallCenterV2 removeObserverWithToken:participantToken];
 }
 
 - (void)testThatItCreatesASystemMessageWhenWeMissedACall
 {
 // given
 XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
 ZMConversation * oneToOneConversation = self.conversationUnderTest;
 [self otherJoinCall];
 WaitForAllGroupsToBeEmpty(0.5);
 NSUInteger messageCount = oneToOneConversation.messages.count;
 
 // when
 {
 [self otherLeavesUnansweredCall];
 WaitForAllGroupsToBeEmpty(0.5);
 }
 
 // then
 // we receive a systemMessage that we missed a call
 {
 XCTAssertEqual(oneToOneConversation.messages.count, messageCount+1u);
 id<ZMConversationMessage> systemMessage = oneToOneConversation.messages.lastObject;
 XCTAssertNotNil(systemMessage.systemMessageData);
 XCTAssertEqual(systemMessage.systemMessageData.systemMessageType, ZMSystemMessageTypeMissedCall);
 }
 }

 */
