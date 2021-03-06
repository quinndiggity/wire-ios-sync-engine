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
import avs

public protocol AVSWrapperType {
    init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?)
    func callState(conversationId: UUID) -> CallState
    func startCall(conversationId: UUID, video: Bool) -> Bool
    func answerCall(conversationId: UUID) -> Bool
    func endCall(conversationId: UUID)
    func rejectCall(conversationId: UUID)
    func close()
    func received(callEvent: CallEvent)
    func toggleVideo(conversationID: UUID, active: Bool)
    
    func isVideoCall(conversationId: UUID) -> Bool
    func setVideoSendActive(userId: UUID, active: Bool)
    func enableAudioCbr(shouldUseCbr: Bool)
    func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken)
}

/// Wraps AVS calls for dependency injection and better testing
public class AVSWrapper : AVSWrapperType {
    
    required public init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?) {
        let resultValue = wcall_init(
            userId.transportString(),
            clientId,
            ReadyHandler,
            SendCallMessageHandler,
            IncomingCallHandler,
            MissedCallHandler,
            AnsweredCallHandler,
            EstablishedCallHandler,
            ClosedCallHandler,
            observer)
        
        if resultValue != 0 {
            fatal("Failed to initialise AVS")
        }
        
        wcall_set_video_state_handler({ (state, _) in
            guard let state = ReceivedVideoState(rawValue: UInt(state)) else { return }
            
            DispatchQueue.main.async {
                WireCallCenterV3VideoNotification(receivedVideoState: state).post()
            }
        })
        

        wcall_set_audio_cbr_enabled_handler({ _ in
            DispatchQueue.main.async {
                WireCallCenterCBRCallNotification().post()
            }
        })
    }
    
    public func callState(conversationId: UUID) -> CallState {
        return CallState(wcallState:wcall_get_state(conversationId.transportString()))
    }
    
    public func startCall(conversationId: UUID, video isVideo: Bool) -> Bool {
        let didStart = wcall_start(conversationId.transportString(), (Bool(isVideo) ? 1 : 0))
        return didStart == 0
    }
    
    public func answerCall(conversationId: UUID) -> Bool {
        let didAnswer = wcall_answer(conversationId.transportString())
        return didAnswer == 0
    }
    
    public func endCall(conversationId: UUID) {
        wcall_end(conversationId.transportString())
    }
    
    public func rejectCall(conversationId: UUID) {
        wcall_reject(conversationId.transportString())
    }
    
    public func close(){
        wcall_close()
    }
    
    public func isVideoCall(conversationId: UUID) -> Bool {
        return (wcall_is_video_call(conversationId.transportString()) == 1)
    }
    
    public func setVideoSendActive(userId: UUID, active: Bool) {
        wcall_set_video_send_active(userId.transportString(), active ? 1 : 0)
    }
    
    public func enableAudioCbr(shouldUseCbr: Bool) {
        wcall_enable_audio_cbr(shouldUseCbr ? 1 : 0)
    }

    public func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken) {
        wcall_resp(Int32(httpStatus), "", context)
    }
    
    public func received(callEvent: CallEvent) {
        callEvent.data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
            let currentTime = UInt32(callEvent.currentTimestamp.timeIntervalSince1970)
            let serverTime = UInt32(callEvent.serverTimestamp.timeIntervalSince1970)
            
            wcall_recv_msg(bytes, callEvent.data.count, currentTime, serverTime, callEvent.conversationId.transportString(), callEvent.userId.transportString(), callEvent.clientId)
        }
    }
    
    public func toggleVideo(conversationID: UUID, active: Bool) {
        wcall_set_video_send_active(conversationID.transportString(), active ? 1 : 0)
    }
}
