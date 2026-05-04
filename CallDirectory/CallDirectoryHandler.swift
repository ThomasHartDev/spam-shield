import Foundation
import CallKit

final class CallDirectoryHandler: CXCallDirectoryProvider {
    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        // CallKit requires numbers to be sorted ascending and added via the
        // ...withNextSequentialPhoneNumber: API. We do a full reload each time;
        // incremental mode is overkill for a personal-scale blocklist.
        let blocked = BlocklistStore.shared.blockedNumbers().sorted()
        for number in blocked {
            context.addBlockingEntry(withNextSequentialPhoneNumber: number)
        }

        let labeled = BlocklistStore.shared.labeledNumbers()
            .sorted { $0.number < $1.number }
        for entry in labeled {
            context.addIdentificationEntry(
                withNextSequentialPhoneNumber: entry.number,
                label: entry.label
            )
        }

        context.completeRequest()
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext,
                       withError error: Error) {
        // The system logs this; nothing useful for us to do here.
    }
}
