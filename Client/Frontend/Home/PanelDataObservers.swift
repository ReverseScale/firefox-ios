/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Deferred
import Shared

public let ActivityStreamTopSiteCacheSize: Int32 = 16

private let log = Logger.browserLogger

protocol DataObserver {
    var profile: Profile { get }
    weak var delegate: DataObserverDelegate? { get set }
    
    func invalidate(highlights: Bool)
}

@objc protocol DataObserverDelegate: class {
    func didInvalidateDataSources()
    func willInvalidateDataSources()
}

open class PanelDataObservers {
    var activityStream: DataObserver

    init(profile: Profile) {
        self.activityStream = ActivityStreamDataObserver(profile: profile)
    }
}

class ActivityStreamDataObserver: DataObserver {
    let profile: Profile
    weak var delegate: DataObserverDelegate?
    private var invalidationTime = OneMinuteInMilliseconds * 15
    private var lastInvalidation = Date.now()

    fileprivate let events = [NotificationFirefoxAccountChanged, NotificationProfileDidFinishSyncing, NotificationPrivateDataClearedHistory]

    init(profile: Profile) {
        self.profile = profile
        self.profile.history.setTopSitesCacheSize(ActivityStreamTopSiteCacheSize)
        events.forEach { NotificationCenter.default.addObserver(self, selector: #selector(self.notificationReceived(_:)), name: $0, object: nil) }
    }

    deinit {
        events.forEach { NotificationCenter.default.removeObserver(self, name: $0, object: nil) }
    }
    
    func invalidate(highlights: Bool) {
        guard !profile.isShutdown else {
            return
        }

        self.delegate?.willInvalidateDataSources()

        let notify = {
            self.delegate?.didInvalidateDataSources()
        }

        let refreshTopsites: () -> Success = {
            return self.profile.history.refreshTopSitesCache() >>> succeed
        }

        let shouldInvalidate = highlights ? true : (Date.now() - lastInvalidation > invalidationTime)
        lastInvalidation = shouldInvalidate ? Date.now() : lastInvalidation

        self.profile.recommendations.repopulateAll(shouldInvalidate, topsitesLimit: 16).upon() { _ in
            self.delegate?.didInvalidateDataSources()
        }
    }
    
    @objc func notificationReceived(_ notification: Notification) {
        switch notification.name {
        case NotificationProfileDidFinishSyncing, NotificationFirefoxAccountChanged, NotificationPrivateDataClearedHistory:
            invalidate(highlights: true)
        default:
            log.warning("Received unexpected notification \(notification.name)")
        }
    }
}
