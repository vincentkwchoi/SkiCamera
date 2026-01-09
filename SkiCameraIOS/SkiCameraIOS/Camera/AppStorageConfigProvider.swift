//
//  AppStorageConfigProvider.swift
//  SkiCameraIOS
//
//  Created by Photon Juniper on 2024/8/21.
//
import Foundation
import LockedCameraCapture

struct AppStorageConfigProvider : Sendable {
    let rootURL: URL?
    let isLockedCapture: Bool
}

extension AppStorageConfigProvider {
    static let standard = AppStorageConfigProvider(
        rootURL: getStandardRootURL(),
        isLockedCapture: false
    )
}

@available(iOS 18, *)
extension AppStorageConfigProvider {
    init(_ session: LockedCameraCaptureSession) {
        self.rootURL = session.sessionContentURL
        self.isLockedCapture = true
    }
}

private func getStandardRootURL() -> URL? {
    try? FileManager.default.url(
        for: .documentDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
}
