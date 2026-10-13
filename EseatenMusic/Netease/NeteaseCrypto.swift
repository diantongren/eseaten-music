import CommonCrypto
import CryptoKit
import Foundation

/// 网易云接口的两种请求加密
///
/// - weapi（网页端，`music.163.com/weapi/...`）：JSON 先用固定的 presetKey 做 AES-128-CBC 并转 base64，
///   再用客户端自选的 secretKey 加密一次得到 `params`；secretKey 倒序后做无填充 RSA（e = 65537）得到 `encSecKey`。
///   secretKey 由客户端决定，所以这里固定一个，并预先算好它的 RSA 密文，省掉大数运算。
/// - eapi（客户端，`interface.music.163.com/eapi/...`）：把 `/api/...` 路径、JSON 和两者的 MD5 摘要
///   拼成一个字符串，用固定 key 做 AES-128-ECB，结果转大写十六进制作为 `params`。
enum NeteaseCrypto {
    private static let presetKey = "0CoJUm6Qyw8W8jud"
    private static let iv = "0102030405060708"
    /// 自选的 16 位 secretKey
    private static let secretKey = "EseatenMusic2026"
    /// `secretKey` 倒序后的 RSA 密文，模数是网易云网页端写死的公钥
    private static let encSecKey =
        "c47952d773c040787f3b1dd2bb01058df8c1d4d02bb2edff8128a15293cea587" +
        "a9b8dfba9200b3d70c3b3d1bdbc93e9cf3a666e2320e07e17a35ce53696c669b" +
        "cc6352508763fc261afa5be616b54a5e9023028b36868dd1cdc5d014a68b7d30" +
        "9a6f1094602d8a5315b83ea2b34d1c566079572619bc24f1ee757ca1bded2279"
    private static let eapiKey = "e82ckenh8dichen8"
    private static let eapiSeparator = "-36cd479b6b5-"

    /// weapi 表单字段：`params` + `encSecKey`
    static func weapi(_ json: Data) -> [String: String] {
        let once = aes(json, key: presetKey, iv: iv).base64EncodedData()
        let twice = aes(once, key: secretKey, iv: iv).base64EncodedString()
        return ["params": twice, "encSecKey": encSecKey]
    }

    /// eapi 表单字段：`params`
    /// - Parameter apiPath: 摘要用的内部路径，例如 `/api/song/enhance/player/url/v1`
    static func eapi(apiPath: String, json: Data) -> [String: String] {
        let text = String(decoding: json, as: UTF8.self)
        let digest = Insecure.MD5.hash(data: Data("nobody\(apiPath)use\(text)md5forencrypt".utf8))
            .map { String(format: "%02x", $0) }.joined()
        let plain = [apiPath, text, digest].joined(separator: eapiSeparator)
        let cipher = aes(Data(plain.utf8), key: eapiKey, iv: nil)
        return ["params": cipher.map { String(format: "%02X", $0) }.joined()]
    }

    /// AES-128 + PKCS7。传了 iv 用 CBC，否则用 ECB
    private static func aes(_ input: Data, key: String, iv: String?) -> Data {
        let keyBytes = Array(key.utf8)
        // ECB 模式会忽略 iv，传一组 0 即可
        let ivBytes = iv.map { Array($0.utf8) } ?? [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        var options = CCOptions(kCCOptionPKCS7Padding)
        if iv == nil { options |= CCOptions(kCCOptionECBMode) }

        var output = Data(count: input.count + kCCBlockSizeAES128)
        var length = 0
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { bytes in
                CCCrypt(
                    CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options,
                    keyBytes, keyBytes.count, ivBytes,
                    bytes.baseAddress, input.count,
                    out.baseAddress, out.count, &length
                )
            }
        }
        precondition(status == kCCSuccess, "AES 加密失败：\(status)")
        return output.prefix(length)
    }
}
