import Foundation
import AWSS3
import Smithy
import SmithyIdentity
import ClientRuntime

protocol R2ObjectStore: Sendable {
    func getData(key: String) async throws -> (data: Data, etag: String?)?
    func putData(key: String, data: Data, contentType: String?, ifMatch: String?, ifNoneMatch: String?) async throws
    func listKeys(prefix: String) async throws -> [String]
}

final class AWSR2ObjectStore: R2ObjectStore, @unchecked Sendable {
    private let bucket: String
    private let client: S3Client

    nonisolated init(
        endpoint: String,
        bucket: String,
        region: String,
        accessKeyID: String,
        secretAccessKey: String,
        forcePathStyle: Bool
    ) {
        self.bucket = bucket

        let resolver = StaticAWSCredentialIdentityResolver(
            AWSCredentialIdentity(accessKey: accessKeyID, secret: secretAccessKey)
        )
        let config = try! S3Client.S3ClientConfig(
            awsCredentialIdentityResolver: resolver,
            region: region,
            signingRegion: region,
            forcePathStyle: forcePathStyle,
            endpoint: endpoint
        )
        self.client = S3Client(config: config)
    }

    func getData(key: String) async throws -> (data: Data, etag: String?)? {
        do {
            let output = try await client.getObject(input: GetObjectInput(bucket: bucket, key: key))
            guard let body = output.body else { return nil }
            let data = try await body.readData()
            guard let data else { return nil }
            return (data, output.eTag)
        } catch {
            if isNotFound(error) { return nil }
            throw error
        }
    }

    func putData(key: String, data: Data, contentType: String?, ifMatch: String?, ifNoneMatch: String?) async throws {
        let input = PutObjectInput(
            body: .data(data),
            bucket: bucket,
            contentType: contentType,
            ifMatch: ifMatch,
            ifNoneMatch: ifNoneMatch,
            key: key
        )
        _ = try await client.putObject(input: input)
    }

    func listKeys(prefix: String) async throws -> [String] {
        var keys: [String] = []
        var continuationToken: String?

        while true {
            let input = ListObjectsV2Input(
                bucket: bucket,
                continuationToken: continuationToken,
                prefix: prefix
            )
            let page = try await client.listObjectsV2(input: input)

            for item in page.contents ?? [] {
                if let key = item.key {
                    keys.append(key)
                }
            }

            guard page.isTruncated == true,
                  let nextToken = page.nextContinuationToken,
                  !nextToken.isEmpty else {
                break
            }

            continuationToken = nextToken
        }

        return keys
    }

    private func isNotFound(_ error: Error) -> Bool {
        let text = String(describing: error)
        return text.contains("NoSuchKey") || text.contains("NotFound") || text.contains("404")
    }
}
