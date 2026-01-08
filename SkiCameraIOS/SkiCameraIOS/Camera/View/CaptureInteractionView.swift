//
//  InteractionView.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/20.
//
import SwiftUI
import Photos
import AVFoundation
import AVKit

extension View {
    @ViewBuilder
    func onPressCapture(
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void,
        secondaryPress: @escaping () -> Void,
        secondaryRelease: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, *) {
            self.onCameraCaptureEvent { event in
                switch event.phase {
                case .began:
                    onPress()
                case .ended, .cancelled:
                    onRelease()
                default:
                    break
                }
            } secondaryAction: { event in
                switch event.phase {
                case .began:
                    secondaryPress()
                case .ended, .cancelled:
                    secondaryRelease()
                default:
                    break
                }
            }
        } else if #available(iOS 17.2, *) {
            self.background {
                CaptureInteractionView(
                    onPress: onPress,
                    onRelease: onRelease,
                    secondaryPress: secondaryPress,
                    secondaryRelease: secondaryRelease
                )
            }
        } else {
            self
        }
    }
}

@available(iOS 17.2, *)
private struct CaptureInteractionView: UIViewRepresentable {
    var onPress: () -> Void
    var onRelease: () -> Void
    var secondaryPress: () -> Void
    var secondaryRelease: () -> Void
    
    func makeUIView(context: Context) -> some UIView {
        let uiView = UIView()
        let interaction = AVCaptureEventInteraction(primary: { event in
            if event.phase == .began {
                onPress()
            } else if event.phase == .ended || event.phase == .cancelled {
                onRelease()
            }
        }, secondary: { event in
            if event.phase == .began {
                secondaryPress()
            } else if event.phase == .ended || event.phase == .cancelled {
                secondaryRelease()
            }
        })
        
        uiView.addInteraction(interaction)
        return uiView
    }
    
    func updateUIView(_ uiView: UIViewType, context: Context) {
        // ignored
    }
}
