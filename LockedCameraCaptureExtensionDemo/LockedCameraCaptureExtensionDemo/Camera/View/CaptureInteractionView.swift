//
//  InteractionView.swift
//  LockedCameraCaptureExtensionDemo
//
//  Created by Photon Juniper on 2024/8/20.
//
import SwiftUI
import Photos
import AVFoundation
import AVKit

extension View {
    @ViewBuilder
    func onPressCapture(action: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onCameraCaptureEvent { event in
                switch event.phase {
                case .ended:
                    action()
                default:
                    break
                }
            } secondaryAction: { event in
                switch event.phase {
                case .ended:
                    action()
                default:
                    break
                }
            }
        } else if #available(iOS 17.2, *) {
            self.background {
                CaptureInteractionView(action: action)
            }
        } else {
            self
        }
    }
    
    @ViewBuilder
    func onPressCapture(action: @escaping () -> Void, secondaryAction: @escaping () -> Void) -> some View {
        if #available(iOS 18.0, *) {
            self.onCameraCaptureEvent { event in
                switch event.phase {
                case .ended:
                    action()
                default:
                    break
                }
            } secondaryAction: { event in
                switch event.phase {
                case .ended:
                    secondaryAction()
                default:
                    break
                }
            }
        } else if #available(iOS 17.2, *) {
            self.background {
                CaptureInteractionView(action: action, secondaryAction: secondaryAction)
            }
        } else {
            self
        }
    }
}

@available(iOS 17.2, *)
private struct CaptureInteractionView: UIViewRepresentable {
    var action: () -> Void
    var secondaryAction: (() -> Void)?
    
    func makeUIView(context: Context) -> some UIView {
        let uiView = UIView()
        let interaction = AVCaptureEventInteraction(primary: { event in
            if event.phase == .began {
                // Primary action (Volume Up or Capture button)
                action()
            }
        }, secondary: { event in
            if event.phase == .began {
                // Secondary action (Volume Down)
                if let secondaryAction = secondaryAction {
                    secondaryAction()
                } else {
                    action()
                }
            }
        })
        
        uiView.addInteraction(interaction)
        return uiView
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        // ignored
    }
}
