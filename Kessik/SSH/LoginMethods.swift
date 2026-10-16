import Foundation
import CryptoKit
import NIOCore
import NIOSSH
import Citadel

/// Offers this phone's key first, then the password, so a Mac that has the key needs no password.
/// A method the Mac does not allow is skipped.
final class LoginMethods: NIOSSHClientUserAuthenticationDelegate {
    private let username: String
    private var offers: [NIOSSHUserAuthenticationOffer.Offer] = []

    init(username: String, key: Curve25519.Signing.PrivateKey?, password: String?,
         enclaveKey: SecureEnclave.P256.Signing.PrivateKey? = nil) {
        self.username = username
        if let enclaveKey {
            offers.append(.privateKey(.init(privateKey: NIOSSHPrivateKey(secureEnclaveP256Key: enclaveKey))))
        }
        if let key {
            offers.append(.privateKey(.init(privateKey: NIOSSHPrivateKey(ed25519Key: key))))
        }
        if let password, !password.isEmpty {
            offers.append(.password(.init(password: password)))
        }
    }

    func nextAuthenticationType(
        availableMethods: NIOSSHAvailableUserAuthenticationMethods,
        nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>
    ) {
        while !offers.isEmpty {
            let offer = offers.removeFirst()
            switch offer {
            case .privateKey where availableMethods.contains(.publicKey),
                 .password where availableMethods.contains(.password):
                nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(username: username, serviceName: "", offer: offer))
                return
            default:
                continue
            }
        }
        nextChallengePromise.fail(SSHClientError.allAuthenticationOptionsFailed)
    }
}
